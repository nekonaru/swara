import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
import '../services/player_service.dart';
import '../utils/scan_controls.dart';

const List<String> kEqualizerPresets = [
  'Flat',
  'Pop',
  'Rock',
  'Classical',
  'Jazz',
  'Electronic',
  'Hip-Hop',
  'Bass Boost',
  'Vocal',
  'Custom',
];

// Simple per-preset EQ representation (relative gains, for UI reference).
// When a real EQ package is added, these values can be used directly.
const Map<String, List<double>> kPresetBands = {
  'Flat': [0, 0, 0, 0, 0],
  'Pop': [1, 2, 2, 1, 0],
  'Rock': [3, 1, -1, 1, 3],
  'Classical': [2, 0, 0, 0, 2],
  'Jazz': [2, 1, 0, 1, 2],
  'Electronic': [3, 1, 0, 2, 3],
  'Hip-Hop': [3, 2, 0, 0, 1],
  'Bass Boost': [4, 3, 0, 0, 0],
  'Vocal': [-1, 0, 2, 2, 0],
  'Custom': [0, 0, 0, 0, 0],
};

const List<String> _bandLabels = ['60Hz', '250Hz', '1kHz', '4kHz', '16kHz'];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Guard against rapid successive taps on preferences:
  // the save future is awaited and input is disabled while saving.
  bool _savingPrefs = false;

  // Local mirror of the 5 custom EQ gains, so a slider drag only repaints.
  // Every pref write and every platform call happens on onChangeEnd, once the
  // finger is up. See _eqDraft.
  final List<double> _eqDraft = [0, 0, 0, 0, 0];
  bool _eqDraftReady = false;

  // Lazily seeds the drag draft from the persisted gains.
  List<double> _eqDraftFrom(ThemeProvider theme) {
    if (!_eqDraftReady) {
      _eqDraft
        ..clear()
        ..addAll(theme.customEqGains);
      _eqDraftReady = true;
    }
    return _eqDraft;
  }

  // Forget the draft so it is re-seeded from prefs on the next build, used when
  // the preset changes from outside the sliders.
  void _resetEqDraft() {
    _eqDraftReady = false;
  }

  // State for the Data section (backup export/import + art cache).
  bool _busyData = false;
  bool _loadingArt = false;
  ArtCacheUsage? _artUsage;
  // Busy flag while the listening history prune runs.
  bool _busyHistory = false;
  // App version shown in About, loaded once from package info.
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _refreshArtCache();
    _loadAppVersion();
  }

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
  Future<void> _checkForUpdate() async {
    if (_savingPrefs) return;
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
        content: Text(l10n.settingsUpdateAvailableBody(tag, current)),
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
    await _downloadAndInstall(result.downloadUrl!);
  }

  // Download the release APK behind a progress dialog, then hand it to the
  // system installer. Installing with the same signature upgrades in place.
  Future<void> _downloadAndInstall(String downloadUrl) async {
    final l10n = AppLocalizations.of(context)!;
    final progress = ValueNotifier<double>(-1);
    // Non-dismissible while the download runs.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(l10n.settingsUpdateDownloading),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value < 0 ? null : value),
              const SizedBox(height: 12),
              Text(value < 0 ? '…' : '${(value * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    ));
    final path = await UpdateService.instance.downloadApk(
      downloadUrl,
      onProgress: (p) => progress.value = p,
    );
    if (!mounted) return;
    // Close the progress dialog regardless of the outcome.
    Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    if (path == null) {
      _showSnack(l10n.settingsUpdateFailed);
      return;
    }
    final status = await AudioEffectsService.instance.installApk(path);
    if (!mounted) return;
    switch (status) {
      case 'ok':
        // The system installer is up; nothing to say here.
        break;
      case 'no_permission':
        _showSnack(l10n.settingsUpdateInstallFailed);
        break;
      default:
        // The installer would not start. Fall back to the GitHub releases
        // page so the user can still update by hand.
        await _openLink('https://github.com/nekonaru/swara/releases');
        break;
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
      _showSnack(AppLocalizations.of(context)!.dataMeasureFailed(e.toString()));
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
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (!ctx.mounted) return;
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
      setState(() => _busyData = false);
      _showSnack(AppLocalizations.of(context)!
          .dataExportFailed(e.toString()));
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
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              controller.text = data?.text ?? '';
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
      setState(() => _busyData = false);
      _showSnack(AppLocalizations.of(context)!.dataImportDone(
          result.playlistsCreated,
          result.playlistMembersAdded,
          result.favoritesRestored,
          result.listeningEntriesRestored));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyData = false);
      _showSnack(
          AppLocalizations.of(context)!.dataImportFailed(e.toString()));
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
      if (!mounted) return;
      setState(() => _busyData = false);
      _showSnack(
          AppLocalizations.of(context)!.dataClearFailed(e.toString()));
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
      if (!mounted) return;
      setState(() => _busyHistory = false);
      _showSnack(AppLocalizations.of(context)!
          .historyCleanupFailed(e.toString()));
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
  // audio effect control flow.
  // The EQ effect session exists only after a song has played; when
  // none is attached yet, fall back to the active player's raw session id
  // so the panel can still open. If no equalizer app answers, say so
  // instead of pretending it worked.
  Future<void> _openSystemEqualizer() async {
    if (_savingPrefs) return;
    final sessionId = EqualizerService.instance.sessionId ??
        PlayerService.instance.player.androidAudioSessionId;
    if (sessionId == null || sessionId <= 0) return;
    final opened = await AudioEffectsService.instance.openEqualizerPanel(sessionId);
    if (!mounted) return;
    if (!opened) {
      _showSnack(AppLocalizations.of(context)!.eqNoSystemEqualizer);
    }
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
    final lib = context.watch<LibraryProvider>();
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
                    return GestureDetector(
                      onTap: _savingPrefs
                          ? null
                          : () => _savePrefs(
                              () => themeProvider.setAccentColor(i)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: kAccentColors[i],
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(
                                  color:
                                      Theme.of(context).colorScheme.outline,
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
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
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
                        value: 0.8,
                        label: Text(
                            AppLocalizations.of(context)!.dispSmall)),
                    ButtonSegment(
                        value: 0.85,
                        label: Text(
                            AppLocalizations.of(context)!.dispNormal)),
                    ButtonSegment(
                        value: 1.0,
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
          Builder(builder: (context) {
            final ready = EqualizerService.instance.isReady;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready
                          ? Colors.green
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
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              l10n.settingsEqualizerNote,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          // Preset chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: kEqualizerPresets.map((preset) {
                final isSelected = preset == themeProvider.equalizerPreset;
                return ChoiceChip(
                  label: Text(preset),
                  selected: isSelected,
                  onSelected: _savingPrefs
                      ? null
                      : (_) => _savePrefs(() async {
                            await themeProvider.setEqualizerPreset(preset);
                            setState(_resetEqDraft);
                            if (preset == 'Custom') {
                              await EqualizerService.instance.applyCustom(
                                  themeProvider.customEqGains);
                            } else {
                              await EqualizerService.instance
                                  .applyPreset(preset);
                            }
                          }),
                );
              }).toList(),
            ),
          ),
          // Custom 5-band sliders, shown only for the Custom preset.
          // Changes apply live to the DSP and persist to prefs.
          // TODO L10N: English literals, localize after string freeze.
          if (themeProvider.equalizerPreset == 'Custom')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: List.generate(5, (i) {
                  final gains = _eqDraftFrom(themeProvider);
                  return Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(_bandLabels[i],
                            style: const TextStyle(fontSize: 12)),
                      ),
                      Expanded(
                        child: Slider(
                          value: gains[i].clamp(-6.0, 6.0),
                          min: -6,
                          max: 6,
                          divisions: 24,
                          label: '${gains[i].toStringAsFixed(1)} dB',
                          // Drag only repaints: no prefs write, no platform
                          // call per frame. The service throttles and
                          // serializes applies, so even a burst of ticks could
                          // not race, but the drag should stay smooth.
                          onChanged: (v) => setState(() => gains[i] = v),
                          // Finger up: persist and commit the final curve.
                          onChangeEnd: (v) => _savePrefs(() async {
                            final updated = List.of(gains)..[i] = v;
                            await themeProvider.setCustomEqGains(updated);
                            await EqualizerService.instance
                                .applyCustom(updated);
                          }),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${gains[i].toStringAsFixed(1)} dB',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          // EQ band visualizer
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _EqVisualizer(
              preset: themeProvider.equalizerPreset,
              customGains: _eqDraftFrom(themeProvider),
            ),
          ),
          // Open the system equalizer (Wavelet or the built-in panel) for
          // this session, the standard panel flow.
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            leading: const Icon(Icons.tune_outlined),
            title: Text(l10n.eqOpenSystem),
            subtitle: Text(l10n.eqOpenSystemSubtitle),
            onTap: _openSystemEqualizer,
          ),
          const Divider(),

          // -- LIBRARY --
          _SectionHeader(l10n.settingsLibrary),
          ListTile(
            leading: lib.isScanning
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.folder_open_outlined),
            title: Text(l10n.settingsScanFiles),
            subtitle: Text(l10n.settingsScanFilesSubtitle),
            onTap: lib.isScanning ? null : () => lib.forceScanDevice(),
          ),
          ListTile(
            leading: lib.isBulkScanningMetadata
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_sync_outlined),
            title: Text(l10n.settingsScanMissing),
            subtitle: Text(lib.isBulkScanningMetadata
                ? l10n.settingsScanProgress(lib.bulkScanProgress,
                    lib.bulkScanTotal)
                : l10n.settingsScanMissingSubtitle),
            // While a scan runs the tile itself cannot start another one, and
            // the button on the right ends the running one.
            trailing: lib.isBulkScanningMetadata
                ? TextButton(
                    onPressed: lib.bulkScanCancelRequested
                        ? null
                        : () => stopBulkMetadataScan(context),
                    child: Text(l10n.settingsScanCancel),
                  )
                : null,
            onTap: lib.isBulkScanningMetadata
                ? null
                : () => lib.bulkScanMetadata(onlyMissing: true),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l10n.settingsRescanAll),
            subtitle: Text(l10n.settingsRescanAllSubtitle),
            onTap: lib.isBulkScanningMetadata
                ? null
                : () => _confirmRescanAll(context, lib),
          ),
          if (lib.isBulkScanningMetadata)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: LinearProgressIndicator(
                value: lib.bulkScanTotal == 0
                    ? null
                    : lib.bulkScanProgress / lib.bulkScanTotal,
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
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/swara-mark.png',
                width: 40,
                height: 40,
                // The source is much larger than the 40px render; decode at
                // display size instead of the full resolution.
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
            onTap: _checkForUpdate,
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

// Simple EQ bar visualizer mirroring the selected preset curve.
class _EqVisualizer extends StatelessWidget {
  final String preset;
  final List<double> customGains;
  const _EqVisualizer({required this.preset, this.customGains = const [0.0, 0.0, 0.0, 0.0, 0.0]});

  @override
  Widget build(BuildContext context) {
    final bands =
        preset == 'Custom' ? customGains : (kPresetBands[preset] ?? const [0.0, 0.0, 0.0, 0.0, 0.0]);
    final max = bands.map((b) => b.abs()).reduce((a, b) => a > b ? a : b);
    final normalizer = max < 1 ? 1.0 : max;
    final color = Theme.of(context).colorScheme.primary;

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(bands.length, (i) {
          final gain = bands[i];
          final ratio = (gain / normalizer).clamp(-1.0, 1.0);
          final barHeight = (ratio.abs() * 32 + 4).clamp(4.0, 44.0);

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: 24,
                height: barHeight,
                decoration: BoxDecoration(
                  color: gain > 0
                      ? color
                      : gain < 0
                          ? color.withValues(alpha: 0.4)
                          : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Text(_bandLabels[i],
                  style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          );
        }),
      ),
    );
  }
}
