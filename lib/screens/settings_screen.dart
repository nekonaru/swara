import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/language_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/library_provider.dart';
import '../services/backup_service.dart';
import '../services/db_helper.dart';
import '../services/audio_effects_service.dart';
import '../services/update_service.dart';
import '../services/equalizer_service.dart';
import '../services/loudness_service.dart';
import '../services/player_service.dart';
import '../services/snapshot_service.dart';
import '../utils/scan_controls.dart';
import '../widgets/eq_controls.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Guard against rapid successive taps on preferences:
  // the save future is awaited and input is disabled while saving.
  bool _savingPrefs = false;

  // State for the Data section (backup export/import + art cache).
  bool _busyData = false;
  bool _loadingArt = false;
  ArtCacheUsage? _artUsage;
  // Busy flag while the listening history prune runs.
  bool _busyHistory = false;
  // Last backup export, and the live DSP toggle state.
  DateTime? _lastExport;
  List<SnapshotInfo> _snapshots = const <SnapshotInfo>[];
  bool _restoringSnapshot = false;
  bool _loudnessEnabled = false;
  // App version shown in About, loaded once from package info.
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _refreshArtCache();
    _loadAppVersion();
    _loudnessEnabled = LoudnessService.instance.enabled;
    _loadLastExport();
    _loadSnapshots();
    _maybeOfferAutoRestore();
  }

  Future<void> _loadSnapshots() async {
    try {
      final list = await SnapshotService.instance.listSnapshots();
      if (!mounted) return;
      setState(() => _snapshots = list);
    } catch (_) {
      if (mounted) setState(() => _snapshots = const <SnapshotInfo>[]);
    }
  }

  Future<void> _createSnapshotNow() async {
    if (_busyData || _restoringSnapshot) return;
    setState(() => _busyData = true);
    try {
      final info = await SnapshotService.instance.createSnapshot(force: true);
      if (!mounted) return;
      if (info != null) {
        _showSnack(AppLocalizations.of(context)!
            .dataSnapshotItem(_formatExportStamp(info.createdAt),
                _formatBytes(info.bytes)));
      }
      await _loadSnapshots();
    } catch (e) {
      if (mounted) {
        _showSnack(AppLocalizations.of(context)!.dataSnapshotFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _busyData = false);
    }
  }

  Future<void> _restoreSnapshot(SnapshotInfo info) async {
    if (_busyData || _restoringSnapshot) return;
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.dataSnapshotRestoreTitle),
        content: Text(l.dataSnapshotRestoreMessage(_formatExportStamp(info.createdAt))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.dataSnapshotRestore)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _restoringSnapshot = true);
    final libraryProvider = context.read<LibraryProvider>();
    final playlistProvider = context.read<PlaylistProvider>();
    try {
      await SnapshotService.instance.restoreSnapshot(info.name);
      await libraryProvider.loadFromDb();
      await playlistProvider.load();
      if (!mounted) return;
      _showSnack(l.dataSnapshotRestored);
    } catch (e) {
      if (mounted) _showSnack(l.dataSnapshotFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _restoringSnapshot = false);
    }
  }

  Future<void> _deleteSnapshot(SnapshotInfo info) async {
    await SnapshotService.instance.deleteSnapshot(info.name);
    if (!mounted) return;
    _showSnack(AppLocalizations.of(context)!.dataSnapshotDeleted);
    await _loadSnapshots();
  }

  Future<void> _maybeOfferAutoRestore() async {
    try {
      if (await SnapshotService.autoRestoreOffered()) return;
      if (await DBHelper.instance.getSongCount() != 0) {
        await SnapshotService.markAutoRestoreOffered();
        return;
      }
      final latest = (await SnapshotService.instance.listSnapshots()).firstOrNull;
      if (latest == null || !mounted) return;
      final l = AppLocalizations.of(context)!;
      final accept = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.dataSnapshotAutoTitle),
          content: Text(l.dataSnapshotAutoMessage(_formatExportStamp(latest.createdAt))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.dataSnapshotAutoDecline)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.dataSnapshotAutoAccept)),
          ],
        ),
      );
      await SnapshotService.markAutoRestoreOffered();
      if (accept == true && mounted) await _restoreSnapshot(latest);
    } catch (_) {
      // The offer is optional; never block Settings.
    }
  }

  Future<void> _loadLastExport() async {
    final stamp = await BackupService.lastExport();
    if (!mounted) return;
    setState(() => _lastExport = stamp);
  }

  String _formatExportStamp(DateTime stamp) =>
      DateFormat('yyyy-MM-dd HH:mm').format(stamp.toLocal());

  // Read the real version once so About never shows a stale hardcode.
  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {
      // Leave blank when package info is unavailable.
    }
  }

  // Ask GitHub whether a newer release exists and, if it does, offer to
  // download the APK and install it in place (same signature as the
  // installed copy, so no uninstall is needed).
  // Guard the whole check/download/install flow; sharing one APK path and
  // one cancel flag makes concurrent updates unsafe.
  bool _updating = false;

  Future<void> _checkForUpdate() async {
    if (_savingPrefs || _updating) return;
    _updating = true;
    // Rebuild so the About tile visibly disables while work is in flight.
    if (mounted) setState(() {});
    try {
      await _checkForUpdateInner();
    } finally {
      _updating = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _checkForUpdateInner() async {
    final l10n = AppLocalizations.of(context)!;
    // Show the "checking" hint right away; the result replaces it.
    _showSnack(l10n.settingsUpdateChecking);
    final result = await UpdateService.instance.checkForUpdate();
    if (!mounted) return;
    switch (result.outcome) {
      case UpdateOutcome.error:
        _showSnack(l10n.settingsUpdateCheckFailed);
        return;
      case UpdateOutcome.upToDate:
        _showSnack(l10n.settingsUpToDate);
        return;
      case UpdateOutcome.updateAvailable:
        break;
    }
    final tag = result.tagName ?? '';
    final current = result.currentVersion ?? _appVersion;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsUpdateAvailableTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsUpdateAvailableBody(tag, current)),
            const SizedBox(height: 12),
            Text(l10n.updateSignatureOnceHint,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.settingsLater)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.settingsUpdate)),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await _downloadAndInstall(
      result.downloadUrl!,
      digest: result.downloadDigest,
      expectedSize: result.downloadSize,
    );
  }

  // Download the release APK behind a progress dialog, then hand it to the
  // system installer. Installing with the same signature upgrades in place.
  Future<void> _downloadAndInstall(String downloadUrl,
      {String? digest, int? expectedSize}) async {
    final l10n = AppLocalizations.of(context)!;
    final progress = ValueNotifier<double>(-1);
    // Capture the root navigator before the download so the dialog can be
    // closed even after this screen is gone.
    final navigator = Navigator.of(context, rootNavigator: true);
    // Non-dismissible while the download runs; the Cancel button aborts.
    // Keep the future so we never pop a route that hardware Back already
    // closed, and dispose the notifier only after the dialog is gone.
    var dialogClosed = false;
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(l10n.settingsUpdateDownloading),
        actions: [
          TextButton(
              onPressed: () {
                UpdateService.instance.cancelDownload();
                // Acknowledge the tap immediately; the existing guard keeps
                // the later cleanup from popping a second route.
                if (!dialogClosed && navigator.mounted) navigator.pop();
              },
              child: Text(l10n.cancel)),
        ],
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value < 0 ? null : value),
              const SizedBox(height: 12),
              Text(value < 0 ? '...' : '${(value * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    )..whenComplete(() => dialogClosed = true);
    final result = await UpdateService.instance.downloadApk(
      downloadUrl,
      digest: digest,
      expectedSize: expectedSize,
      onProgress: (p) => progress.value = p,
    );
    // Close the progress dialog only if it is still on screen; a hardware
    // Back press may already have popped it while the download ran.
    if (!dialogClosed && navigator.mounted) navigator.pop();
    await dialog.catchError((Object _) {});
    progress.dispose();
    if (!mounted) return;
    final path = result.$1;
    final verified = result.$2;
    final mismatch = result.$3;
    if (path == null) {
      if (UpdateService.instance.lastDownloadCancelled) return;
      _showSnack(mismatch
          ? l10n.settingsUpdateDigestMismatch
          : l10n.settingsUpdateFailed);
      return;
    }
    // The download could not be verified against the publisher. Ask for an
    // explicit consent instead of pushing an unverified APK at the installer.
    if (!verified) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.settingsUpdateUnverifiedTitle),
          content: Text(l10n.settingsUpdateUnverifiedBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.settingsUpdateUnverifiedInstall)),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    final status = await AudioEffectsService.instance.installApk(path);
    if (!mounted) return;
    switch (status) {
      case 'ok':
        // The system installer is up; drop the cached APK so it does not
        // linger in the temp directory forever.
        try {
          await File(path).delete();
        } catch (_) {}
        break;
      case 'no_permission':
        // The user was sent to the grant screen. Keep the verified APK and
        // offer to retry the install instead of forcing a re-download.
        _showSnackWithAction(
          l10n.settingsUpdateInstallPermission,
          label: l10n.settingsUpdateRetryInstall,
          onPressed: () => _retryInstall(path),
        );
        break;
      default:
        // The installer would not start. Fall back to the GitHub releases
        // page so the user can still update by hand.
        await _openLink('https://github.com/nekonaru/swara/releases');
        break;
    }
  }

  Future<void> _retryInstall(String path) async {
    final status = await AudioEffectsService.instance.installApk(path);
    if (!mounted) return;
    if (status == 'ok') {
      try {
        await File(path).delete();
      } catch (_) {}
    } else {
      _showSnack(AppLocalizations.of(context)!.settingsUpdateInstallFailed);
    }
  }

  // Open a link in an external browser.
  // No canLaunchUrl gate: on Android 11+ the http/https check always returns
  // false without a <queries> manifest entry, so the link never opened.
  Future<void> _openLink(String url) async {
    try {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showSnack(AppLocalizations.of(context)!.playerCannotOpenBrowser);
      }
    } catch (_) {
      // Best effort link, never block settings.
      if (!mounted) return;
      _showSnack(AppLocalizations.of(context)!.playerCannotOpenBrowser);
    }
  }

  Future<void> _openDeveloperPage() =>
      _openLink('https://github.com/nekonaru');

  // Short snackbar helper with a mounted guard.
  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Replace the previous message instead of queueing a stack of them.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
        SnackBar(duration: const Duration(seconds: 2), content: Text(message)));
  }

  void _showSnackWithAction(String message,
      {required String label, required VoidCallback onPressed}) {
    if (!mounted) return;
    // Do not hide an existing actionable snackbar: the retry-install action
    // must remain available while other messages come and go.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(seconds: 2),
        content: Text(message),
        action: SnackBarAction(label: label, onPressed: onPressed),
      ),
    );
  }

  // Human readable byte count for the art cache row.
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _refreshArtCache() async {
    if (_loadingArt) return;
    setState(() => _loadingArt = true);
    try {
      final usage = await BackupService.artCacheUsage();
      if (!mounted) return;
      setState(() => _artUsage = usage);
    } catch (e) {
      debugPrint('Backup measure failed: $e');
      _showSnack(AppLocalizations.of(context)!.dataFailedGeneric);
    } finally {
      if (mounted) setState(() => _loadingArt = false);
    }
  }

  // Export the library to JSON and show size + copy button in a dialog.
  Future<void> _exportData() async {
    if (_busyData) return;
    setState(() => _busyData = true);
    try {
      final json = await BackupService.exportLibrary();
      if (!mounted) return;
      setState(() => _busyData = false);
      final l10n = AppLocalizations.of(context)!;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.dataExportTitle),
          content: Text(l10n.dataExportReady(json.length, _formatBytes(json.length))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.close),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final savedName =
                      await BackupService.saveBackupToFile(json);
                  if (savedName == null) return; // user cancelled the picker
                  await BackupService.recordExport();
                  if (!ctx.mounted) return;
                  if (mounted) setState(() => _lastExport = DateTime.now());
                  Navigator.pop(ctx);
                  _showSnack(l10n.dataBackupSavedSaf(savedName));
                } catch (_) {
                  if (ctx.mounted) {
                    _showSnack(l10n.dataFailedGeneric);
                  }
                }
              },
              child: Text(l10n.dataSaveToFile),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: json));
                } catch (_) {
                  if (ctx.mounted) _showSnack(l10n.dataFailedGeneric);
                  return;
                }
                await BackupService.recordExport();
                if (!ctx.mounted) return;
                if (mounted) setState(() => _lastExport = DateTime.now());
                Navigator.pop(ctx);
                _showSnack(l10n.dataCopied);
              },
              child: Text(l10n.dataCopy),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('Backup export failed: $e');
      setState(() => _busyData = false);
      _showSnack(AppLocalizations.of(context)!.dataFailedGeneric);
    }
  }

  // Ask for pasted JSON, offer a paste-from-clipboard button, then import.
  Future<void> _importData() async {
    final controller = TextEditingController();
    final l10n = AppLocalizations.of(context)!;
    final pasted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dataImportTitle),
        // Scrollable so the keyboard never causes overflow on small screens.
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.dataImportPrompt),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: l10n.dataImportHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              try {
                final picked = await FilePickerPlatform.instance.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['json'],
                );
                if (picked.isEmpty) return;
                final path = picked.first.path;
                if (path == null) return;
                final file = File(path);
                // Cap the read so a huge file cannot OOM the UI isolate.
                if (await file.length() > 32 * 1024 * 1024) {
                  if (ctx.mounted) _showSnack(l10n.dataFailedGeneric);
                  return;
                }
                final text = await file.readAsString();
                if (ctx.mounted) Navigator.pop(ctx, text.trim());
              } catch (_) {
                if (ctx.mounted) _showSnack(l10n.dataFailedGeneric);
              }
            },
            child: Text(l10n.dataImportFile),
          ),
          TextButton(
            onPressed: () async {
              try {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (!ctx.mounted) return;
                controller.text = data?.text ?? '';
              } catch (_) {
                if (ctx.mounted) {
                  _showSnack(l10n.dataFailedGeneric);
                }
              }
            },
            child: Text(l10n.dataPaste),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.dataImportAction),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (pasted == null || pasted.isEmpty) return;

    // Confirm before writing anything to the DB.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dataConfirmImportTitle),
        content: Text(l10n.dataConfirmImportMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.dataImportAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyData = true);
    try {
      final result = await BackupService.importLibrary(pasted);
      if (!mounted) return;
      // Refresh library views so restored favorites show up at once.
      try {
        await context.read<LibraryProvider>().loadFromDb();
      } catch (_) {
        // Non fatal: import already succeeded.
      }
      if (!mounted) return;
      try {
        await context.read<PlaylistProvider>().load();
      } catch (_) {
        // Non fatal: playlist screen reloads on open.
      }
      if (!mounted) return;
      // A restore only writes preferences; refresh the live in-memory state
      // too so EQ curves, theme and playback settings update immediately.
      final theme = context.read<ThemeProvider>();
      final language = context.read<LanguageProvider>();
      await theme.load();
      await LoudnessService.instance.load();
      await PlayerService.instance.loadPreferences();
      if (mounted) {
        setState(() =>
            _loudnessEnabled = LoudnessService.instance.enabled);
      }
      // Pushed preferences must reach the live DSP and playback rate now.
      final preset = theme.equalizerPreset;
      if (preset == 'Flat') {
        await EqualizerService.instance.applyPreset('Flat');
      } else if (preset == 'Custom' || preset.startsWith('user:')) {
        await EqualizerService.instance.applyCustom(
          theme.gainsForActivePreset() ?? theme.customEqGains,
          presetToken: preset,
        );
      } else {
        await EqualizerService.instance.applyPreset(preset);
      }
      await PlayerService.instance.reapplyAudioSettings();
      try {
        await language.load();
      } catch (_) {}
      if (!mounted) return;
      final l10nAfter = AppLocalizations.of(context)!;
      setState(() => _busyData = false);
      // One snackbar only: successive showSnackBar calls replace each other,
      // which used to hide the v3 summary behind the skipped-count message.
      final summary = StringBuffer(l10nAfter.dataImportDone(
          result.playlistsCreated,
          result.playlistMembersAdded,
          result.favoritesRestored,
          result.listeningEntriesRestored));
      if (result.songsMatched > 0 ||
          result.songsUnmatched > 0 ||
          result.bookmarksRestored > 0) {
        summary.write(' ');
        summary.write(l10nAfter.dataImportDoneV3(
            result.songsMatched,
            result.metadataRestored,
            result.lyricsRestored,
            result.syncedLyricsRestored,
            result.bookmarksRestored));
      }
      final skipped = StringBuffer();
      if ((result.playlistMembersSkipped +
              result.favoritesSkipped +
              result.listeningEntriesSkipped) >
          0) {
        skipped.write(l10nAfter.dataImportSkipped(
            result.playlistMembersSkipped,
            result.favoritesSkipped,
            result.listeningEntriesSkipped));
      }
      if (result.songsUnmatched > 0 || result.bookmarksSkipped > 0) {
        if (skipped.isNotEmpty) skipped.write(' ');
        skipped.write(l10nAfter.dataImportSkippedV3(
            result.songsUnmatched, result.bookmarksSkipped));
      }
      if (skipped.isNotEmpty) summary.write(' ${skipped.toString()}');
      _showSnack(summary.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyData = false);
      debugPrint('Backup import failed: $e');
      final noMatch = e is FormatException &&
          e.message.contains('no entries matching');
      _showSnack(noMatch
          ? AppLocalizations.of(context)!.dataImportFailedNoMatch
          : AppLocalizations.of(context)!.dataImportFailedCheckJson);
    }
  }

  // Confirm then delete cached art files and clear DB references.
  Future<void> _clearArtCache() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dataClearConfirmTitle),
        content: Text(l10n
            .dataClearConfirmMessage(_artUsage?.files ?? 0)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.dataClear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyData = true);
    try {
      final deleted = await BackupService.clearArtCache();
      if (!mounted) return;
      try {
        await context.read<LibraryProvider>().loadFromDb();
      } catch (_) {
        // Non fatal: list refresh only.
      }
      await _refreshArtCache();
      if (!mounted) return;
      setState(() => _busyData = false);
      _showSnack(AppLocalizations.of(context)!.dataArtCleared(deleted));
    } catch (e) {
      debugPrint('Clear art cache failed: $e');
      if (!mounted) return;
      setState(() => _busyData = false);
      _showSnack(AppLocalizations.of(context)!.dataFailedGeneric);
    }
  }

  // Manual, opt-in cleanup of the listening history. It never runs on its
  // own because the dashboard totals are computed from these rows, so the
  // dialog spells out that those numbers will go down.
  Future<void> _cleanupHistory() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.historyCleanupDialogTitle),
        content: Text(l10n.historyCleanupMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.historyCleanupAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyHistory = true);
    try {
      final deleted = await DBHelper.instance.pruneListeningEntries();
      if (!mounted) return;
      setState(() => _busyHistory = false);
      _showSnack(AppLocalizations.of(context)!.historyCleanupDone(deleted));
    } catch (e) {
      debugPrint('History cleanup failed: $e');
      if (!mounted) return;
      setState(() => _busyHistory = false);
      _showSnack(AppLocalizations.of(context)!.dataFailedGeneric);
    }
  }

  Future<void> _savePrefs(Future<void> Function() save) async {
    if (_savingPrefs) return;
    setState(() => _savingPrefs = true);
    try {
      await save();
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
    }
  }

  // Open the system equalizer panel for this session, using the standard
  // audio effect control flow. The EQ effect session exists only after a
  // song has played; when none is attached yet, fall back to the active
  // player's raw session id so the panel can still open. When no equalizer
  // app answers (or no session exists), fall back to the in-app equalizer
  // sheet so the button always does something useful.
  Future<void> _openSystemEqualizer() async {
    if (_savingPrefs) return;
    final sessionId = EqualizerService.instance.sessionId ??
        PlayerService.instance.player.androidAudioSessionId;
    final opened = (sessionId != null && sessionId > 0)
        ? await AudioEffectsService.instance.openEqualizerPanel(sessionId)
        : false;
    if (!mounted) return;
    if (opened) return;
    await _showInAppEqualizerSheet();
  }

  // Bottom sheet hosting the in-app equalizer (presets + custom bands).
  // Shown when no system equalizer app is installed, so the EQ is always
  // reachable from this button.
  Future<void> _showInAppEqualizerSheet() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.eqInAppTitle,
                        style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      l10n.eqInAppSubtitle,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const EqControls(),
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }

  // Returns the localized display name for an accent color index.
  String _accentName(AppLocalizations l10n, int index) {
    switch (index) {
      case 1:
        return l10n.settingsAccentBlue;
      case 2:
        return l10n.settingsAccentTeal;
      case 3:
        return l10n.settingsAccentGreen;
      case 4:
        return l10n.settingsAccentOrange;
      case 5:
        return l10n.settingsAccentRed;
      case 6:
        return l10n.settingsAccentDeepPurple;
      case 7:
        return l10n.settingsAccentPink;
      case 8:
        return l10n.settingsAccentCyan;
      case 9:
        return l10n.settingsAccentLightGreen;
      default:
        return l10n.settingsAccentPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final languageProvider = context.watch<LanguageProvider>();
    final libView = context.select<LibraryProvider, (bool, bool, int, int, bool, int)>((lib) => (
      lib.isScanning,
      lib.isBulkScanningMetadata,
      lib.bulkScanProgress,
      lib.bulkScanTotal,
      lib.bulkScanCancelRequested,
      lib.totalCount,
    ));
    final lib = context.read<LibraryProvider>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          // -- LANGUAGE --
          _SectionHeader(l10n.languageSection),
          RadioGroup<String>(
            groupValue: languageProvider.locale.languageCode,
            onChanged: (v) {
              if (_savingPrefs || v == null) return;
              _savePrefs(() => languageProvider.setLocale(Locale(v)));
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: Text(l10n.languageEnglish),
                  subtitle: Text(l10n.languageSubtitle),
                  value: 'en',
                ),
                RadioListTile<String>(
                  title: Text(l10n.languageIndonesian),
                  subtitle: Text(l10n.languageSubtitle),
                  value: 'id',
                ),
              ],
            ),
          ),
          const Divider(),

          // -- APPEARANCE --
          _SectionHeader(l10n.settingsAppearance),
          RadioGroup<ThemeMode>(
            groupValue: themeProvider.themeMode,
            onChanged: (v) {
              if (_savingPrefs || v == null) return;
              _savePrefs(() => themeProvider.setThemeMode(v));
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(
                  title: Text(l10n.settingsFollowSystem),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: Text(l10n.settingsLight),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text(l10n.settingsDark),
                  value: ThemeMode.dark,
                ),
              ],
            ),
          ),
          const Divider(),

          // -- ACCENT COLOR --
          _SectionHeader(l10n.settingsAccentColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _accentName(l10n, themeProvider.accentColorIndex),
                  style:
                      TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(kAccentColors.length, (i) {
                    final isSelected = i == themeProvider.accentColorIndex;
                    return Tooltip(
                      message: _accentName(l10n, i),
                      child: Semantics(
                        label: _accentName(l10n, i),
                        selected: isSelected,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _savingPrefs
                              ? null
                              : () => _savePrefs(
                                  () => themeProvider.setAccentColor(i)),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: kAccentColors[i],
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                          width: 3)
                                      : null,
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: kAccentColors[i]
                                                .withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: isSelected
                                    ? Icon(
                                        Icons.check,
                                        // Light accents need a dark check,
                                        // dark accents a light one.
                                        color: kAccentColors[i]
                                                    .computeLuminance() >
                                                0.5
                                            ? Colors.black
                                            : Colors.white,
                                        size: 18,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const Divider(),

          _SectionHeader(AppLocalizations.of(context)!.dispSection),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!.dispTextScale),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  segments: [
                    ButtonSegment(
                        value: kTextScaleSmall,
                        label: Text(
                            AppLocalizations.of(context)!.dispSmall)),
                    ButtonSegment(
                        value: kTextScaleNormal,
                        label: Text(
                            AppLocalizations.of(context)!.dispNormal)),
                    ButtonSegment(
                        value: kTextScaleLarge,
                        label: Text(
                            AppLocalizations.of(context)!.dispLarge)),
                  ],
                  // Keep single selection in sync with the provider value.
                  selected: {themeProvider.textScale},
                  onSelectionChanged: _savingPrefs
                      ? null
                      : (selection) => _savePrefs(
                          () => themeProvider.setTextScale(selection.first)),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: Text(AppLocalizations.of(context)!.materialYouTitle),
                  subtitle: Text(
                      AppLocalizations.of(context)!.materialYouSubtitle),
                  secondary: const Icon(Icons.palette_outlined),
                  value: themeProvider.dynamicColor,
                  onChanged: _savingPrefs
                      ? null
                      : (v) =>
                          _savePrefs(() => themeProvider.setDynamicColor(v)),
                ),
                SwitchListTile(
                  title: Text(AppLocalizations.of(context)!.amoledTitle),
                  subtitle: Text(
                      AppLocalizations.of(context)!.amoledSubtitle),
                  secondary: const Icon(Icons.contrast_outlined),
                  value: themeProvider.amoledBlack,
                  onChanged: _savingPrefs
                      ? null
                      : (v) =>
                          _savePrefs(() => themeProvider.setAmoledBlack(v)),
                ),
              ],
            ),
          ),
          const Divider(),

          // -- PLAYBACK --
          _SectionHeader(l10n.settingsPlayback),
          // Smart shuffle switch. Reads the persisted flag straight from the service,
          // the same way the crossfade switch below does.
          AnimatedBuilder(
            animation: PlayerService.instance,
            builder: (context, _) => SwitchListTile(
              title: Text(l10n.settingsSmartShuffle),
              subtitle: Text(l10n.settingsSmartShuffleSubtitle),
              secondary: const Icon(Icons.auto_awesome_outlined),
              value: PlayerService.instance.smartShuffle,
              onChanged: (v) =>
                  setState(() => PlayerService.instance.setSmartShuffle(v)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_to_home_screen_outlined),
            title: Text(l10n.settingsQuickTile),
            subtitle: Text(l10n.settingsQuickTileSubtitle),
          ),
          SwitchListTile(
            title: Text(l10n.settingsCrossfade),
            subtitle: Text(l10n.settingsCrossfadeSubtitle),
            secondary: const Icon(Icons.swap_horiz_outlined),
            value: PlayerService.instance.crossfadeEnabled,
            onChanged: (v) =>
                setState(() => PlayerService.instance.setCrossfadeEnabled(v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!.xfDuration(
                    PlayerService.instance.crossfadeSeconds)),
                Slider(
                  value: PlayerService.instance.crossfadeSeconds.toDouble(),
                  min: 0,
                  max: 12,
                  divisions: 12,
                  label: '${PlayerService.instance.crossfadeSeconds}s',
                  onChanged: (v) => setState(() =>
                      PlayerService.instance.crossfadeDuration =
                          Duration(seconds: v.round())),
                  onChangeEnd: (v) => PlayerService.instance
                      .setCrossfadeSeconds(v.round()),
                ),
              ],
            ),
          ),
          const Divider(),

          // -- EQUALIZER --
          _SectionHeader(l10n.settingsEqualizer),
          // Live state of the DSP. isReady is false until the device actually
          // reported usable bands, so this must not claim "Active" blindly.
          ValueListenableBuilder<bool>(
            valueListenable: EqualizerService.instance.readyNotifier,
            builder: (context, ready, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ready
                        ? AppLocalizations.of(context)!.eqActive
                        : AppLocalizations.of(context)!.eqUnavailable,
                    style:
                        TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              l10n.settingsEqualizerNote,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          // Preset chips, Custom band sliders and visualizer (shared with
          // the in-app equalizer bottom sheet).
          const EqControls(),
          // Open the system equalizer for this session; falls back to the
          // in-app equalizer sheet when no system panel exists.
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            leading: const Icon(Icons.tune_outlined),
            title: Text(l10n.eqOpenSystem),
            subtitle: Text(l10n.eqOpenSystemSubtitle),
            onTap: _openSystemEqualizer,
          ),
          SwitchListTile(
            title: Text(l10n.loudnessNormalization),
            subtitle: Text(l10n.loudnessNormalizationSubtitle),
            secondary: const Icon(Icons.volume_up_outlined),
            value: _loudnessEnabled,
            onChanged: (v) async {
              setState(() => _loudnessEnabled = v);
              await LoudnessService.instance.setEnabled(v);
              if (v) {
                unawaited(LoudnessService.instance
                    .attach(PlayerService.instance.activePlayer));
              }
            },
          ),
          const Divider(),

          // -- LIBRARY --
          _SectionHeader(l10n.settingsLibrary),
          ListTile(
            leading: const Icon(Icons.notifications_none_outlined),
            title: Text(l10n.settingsNotifications),
            subtitle: Text(l10n.settingsNotificationsSubtitle,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.homeSettings,
              onPressed: () async {
                final status = await Permission.notification.status;
                if (status.isPermanentlyDenied || status.isGranted) {
                  await openAppSettings();
                } else {
                  await Permission.notification.request();
                }
              },
            ),
          ),
          ListTile(
            leading: libView.$1
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.folder_open_outlined),
            title: Text(l10n.settingsScanFiles),
            subtitle: Text(l10n.settingsScanFilesSubtitle),
            onTap: libView.$1 ? null : () => lib.forceScanDevice(),
          ),
          ListTile(
            leading: libView.$2
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_sync_outlined),
            title: Text(l10n.settingsScanMissing),
            subtitle: Text(libView.$2
                ? l10n.settingsScanProgress(libView.$3,
                    libView.$4)
                : l10n.settingsScanMissingSubtitle),
            // While a scan runs the tile itself cannot start another one, and
            // the button on the right ends the running one.
            trailing: libView.$2
                ? TextButton(
                    onPressed: libView.$5
                        ? null
                        : () => stopBulkMetadataScan(context),
                    child: Text(l10n.settingsScanCancel),
                  )
                : null,
            onTap: libView.$2
                ? null
                : () => lib.bulkScanMetadata(onlyMissing: true),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l10n.settingsRescanAll),
            subtitle: Text(l10n.settingsRescanAllSubtitle),
            onTap: libView.$2
                ? null
                : () => _confirmRescanAll(context, lib),
          ),
          if (libView.$2)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: LinearProgressIndicator(
                value: libView.$4 == 0
                    ? null
                    : libView.$3 / libView.$4,
              ),
            ),
          const Divider(),

          // -- DATA (backup + cache) --
          _SectionHeader(AppLocalizations.of(context)!.dataSection),
          ListTile(
            leading: _busyData
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_outlined),
            title: Text(AppLocalizations.of(context)!.dataExport),
            subtitle:
                Text(AppLocalizations.of(context)!.dataExportSubtitle),
            onTap: _busyData ? null : _exportData,
          ),
          ListTile(
            leading: _busyData
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined),
            title: Text(AppLocalizations.of(context)!.dataImport),
            subtitle:
                Text(AppLocalizations.of(context)!.dataImportSubtitle),
            onTap: _busyData ? null : _importData,
          ),
          _SectionHeader(AppLocalizations.of(context)!.dataSnapshotsSection),
          ListTile(
            leading: const Icon(Icons.save_outlined),
            title: Text(AppLocalizations.of(context)!.dataSnapshotCreate),
            subtitle: Text(AppLocalizations.of(context)!.dataNever),
            onTap: (_busyData || _restoringSnapshot) ? null : _createSnapshotNow,
          ),
          if (_snapshots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(AppLocalizations.of(context)!.dataSnapshotEmpty),
            ),
          for (final snapshot in _snapshots)
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text(AppLocalizations.of(context)!.dataSnapshotItem(
                  _formatExportStamp(snapshot.createdAt),
                  _formatBytes(snapshot.bytes))),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.restore_outlined),
                    tooltip: AppLocalizations.of(context)!.dataSnapshotRestore,
                    onPressed: (_busyData || _restoringSnapshot)
                        ? null
                        : () => _restoreSnapshot(snapshot),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: AppLocalizations.of(context)!.dataSnapshotDelete,
                    onPressed: (_busyData || _restoringSnapshot)
                        ? null
                        : () => _deleteSnapshot(snapshot),
                  ),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: Text(AppLocalizations.of(context)!.dataLastExport),
            subtitle: Text(_lastExport == null
                ? AppLocalizations.of(context)!.dataNever
                : _formatExportStamp(_lastExport!)),
          ),
          ListTile(
            leading: _loadingArt
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.image_outlined),
            title: Text(AppLocalizations.of(context)!.dataArtCache),
            subtitle: Text(_artUsage == null
                ? AppLocalizations.of(context)!.dataArtCacheMeasuring
                : AppLocalizations.of(context)!.dataArtCacheUsage(
                    _formatBytes(_artUsage!.bytes), _artUsage!.files)),
            trailing: TextButton(
              onPressed:
                  (_busyData || _loadingArt) ? null : () => _refreshArtCache(),
              child: Text(AppLocalizations.of(context)!.dataRefresh),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(AppLocalizations.of(context)!.dataClearArtCache),
            subtitle: Text(
                AppLocalizations.of(context)!.dataClearArtCacheSubtitle),
            onTap: (_busyData || _loadingArt) ? null : _clearArtCache,
          ),
          ListTile(
            leading: _busyHistory
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.history_toggle_off),
            title: Text(AppLocalizations.of(context)!.historyCleanupTitle),
            subtitle: Text(
                AppLocalizations.of(context)!.historyCleanupSubtitle),
            onTap: _busyHistory ? null : _cleanupHistory,
          ),
          const Divider(),

          // -- ABOUT --
          _SectionHeader(l10n.settingsAbout),
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/swara-mark.png',
                width: 40,
                height: 40,
                cacheWidth: 80,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.music_note_outlined),
              ),
            ),
            title: const Text('Swara'),
            subtitle: Text(_appVersion.isEmpty
                ? 'v...'
                : l10n.settingsAboutVersion(_appVersion)),
            trailing: Tooltip(
              message: l10n.settingsCheckForUpdate,
              child: const Icon(Icons.refresh, size: 22),
            ),
            onTap: _updating ? null : _checkForUpdate,
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l10n.settingsDeveloper),
            subtitle: Text(l10n.settingsDeveloperName),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: _openDeveloperPage,
          ),

          // -- SUPPORT --
          _SectionHeader(l10n.donateTitle),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(l10n.donateTitle),
            subtitle: Text(l10n.donateSubtitle),
            trailing: const Icon(Icons.favorite, size: 20),
            onTap: _showSupportSheet,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // Show the support picker. Kept as one calm row instead of four
  // permanent sponsor buttons; the list appears only on tap.
  Future<void> _showSupportSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final options = <(String, String, String, IconData)>[
      (l10n.donateGithub, 'github.com/sponsors/nekonaru', 'https://github.com/sponsors/nekonaru', Icons.favorite),
      (l10n.donateSaweria, 'saweria.co/nekonaruu', 'https://saweria.co/nekonaruu', Icons.favorite),
      (l10n.donateSociabuzz, 'sociabuzz.com/nekonaru/donate', 'https://sociabuzz.com/nekonaru/donate', Icons.favorite),
      (l10n.donateBagibagi, 'bagibagi.co/Nekonaru', 'https://bagibagi.co/Nekonaru', Icons.favorite),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(l10n.donateTitle,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final (title, subtitle, url, icon) in options)
              ListTile(
                leading: Icon(icon),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  _openLink(url);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _confirmRescanAll(BuildContext context, LibraryProvider lib) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsRescanTitle),
        content: Text(l10n.settingsRescanMessage(lib.totalCount)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              lib.bulkScanMetadata(onlyMissing: false);
            },
            child: Text(l10n.settingsRescanStart),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}

