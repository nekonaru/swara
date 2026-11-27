
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/v5_strings.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../services/backup_service.dart';
import '../services/db_helper.dart';
import '../services/extra_features_service.dart';
import '../services/m3u_service.dart';
import '../widgets/swara_empty_state.dart';

/// Extra tools introduced in v5. All offline, all user confirmed.
class V5ExtrasScreen extends StatefulWidget {
  const V5ExtrasScreen({super.key});

  @override
  State<V5ExtrasScreen> createState() => _V5ExtrasScreenState();
}

class _V5ExtrasScreenState extends State<V5ExtrasScreen> {
  List<Map<String, Object?>> _trash = const [];
  List<String> _searchHistory = const [];
  int _goalMinutes = 0;
  int _todayMinutes = 0;
  Map<int, int> _hourly = const {};
  Map<int, int> _weekday = const {};
  int _queueRows = 5;
  bool _compact = false;
  String? _volumeFilter;
  List<(String, int)> _folderRows = const [];
  bool _busy = false;

  Future<void> _load() async {
    if (!mounted) return;
    final lib = context.read<LibraryProvider>();
    _trash = await DBHelper.instance.getTrashEntries();
    _searchHistory = await SearchHistoryService.recent();
    _goalMinutes = await ListeningGoalService.targetMinutes();
    _queueRows = await WidgetSettingsService.queueLength();
    _compact = await WidgetSettingsService.compact();
    _volumeFilter = lib.volumeFilter;
    final now = DateTime.now();
    _todayMinutes = (await DBHelper.instance.getListeningMsSince(
            DateTime(now.year, now.month, now.day).toIso8601String())) ~/
        60000;
    _hourly = await DBHelper.instance.getHourlyDistribution();
    _weekday = await DBHelper.instance.getWeekdayDistribution();
    _folderRows = _rowsForFolders(lib.songs);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _load().catchError((Object _) {});
  }

  Future<void> _confirm(String title, String message, Future<void> Function() action) async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {} finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final lib = context.read<LibraryProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(V5.storageReport)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(V5.trash, [
            if (_trash.isEmpty)
              SwaraEmptyState(
                icon: Icons.delete_outline,
                title: V5.trashEmpty,
              ),
            for (final entry in _trash)
              ListTile(
                title: Text((entry['title'] as String?)?.isEmpty == true
                    ? (entry['path'] as String? ?? '')
                    : entry['title'] as String),
                subtitle: Text(entry['deletedAt'] as String? ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore_outlined),
                      tooltip: V5.restore,
                      onPressed: _busy
                          ? null
                          : () => _confirm(
                                V5.restore,
                                V5.restoreConfirm(entry['title'] as String? ?? ''),
                                () async {
                                  await lib.restoreFromTrash(
                                      entry['songId'] as int);
                                },
                              ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever_outlined),
                      tooltip: V5.removeForever,
                      onPressed: _busy
                          ? null
                          : () => _confirm(
                                V5.removeForever,
                                V5.permanentConfirm(
                                    entry['title'] as String? ?? ''),
                                () => DBHelper.instance.deleteTrashEntry(
                                    entry['songId'] as int),
                              ),
                    ),
                  ],
                ),
              ),
            if (_trash.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: Text(V5.clearTrash),
                onTap: _busy
                    ? null
                    : () => _confirm(V5.clearTrash, V5.clearTrashConfirm,
                        () => DBHelper.instance.clearTrash()),
              ),
          ]),
          _section(V5.verifyBackup, [
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(V5.verifyBackup),
              onTap: _busy ? null : _verifyBackup,
            ),
          ]),
          _section(V5.storageReport, [
            for (final folder in _folderRows)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.$1),
                trailing: Text('${folder.$2}'),
              ),
          ]),
          _section(V5.goal, [
            ListTile(
              title: Text(V5.minutesToday(_todayMinutes)),
              subtitle: Text(_goalMinutes > 0
                  ? '$_goalMinutes ${V5.goalMinutes}'
                  : V5.noGoal),
              trailing: TextButton(
                onPressed: _editGoal,
                child: Text(l.edit),
              ),
            ),
          ]),
          _section(V5.reports, [
            for (final entry in _hourly.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
              ListTile(
                title: Text('${entry.key}:00'),
                trailing: Text('${entry.value ~/ 60000} m'),
              ),
            for (final entry in _weekday.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
              ListTile(
                title: Text(V5.day(entry.key)),
                trailing: Text('${entry.value ~/ 60000} m'),
              ),
          ]),
          _section(V5.diagnostics, [
            for (final line in DiagnosticsService.instance.lines)
              ListTile(title: Text(line, style: const TextStyle(fontSize: 12))),
            if (DiagnosticsService.instance.lines.isEmpty)
              SwaraEmptyState(
                icon: Icons.check_circle_outline,
                title: V5.diagnosticsEmpty,
              ),
            if (DiagnosticsService.instance.lines.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: Text(V5.share),
                onTap: () async {
                  try {
                    await SharePlus.instance.share(ShareParams(
                        text: DiagnosticsService.instance.exportText()));
                  } catch (_) {}
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(V5.clearHistory),
                onTap: () => _confirm(V5.clearHistory, V5.clearHistory,
                    () async => DiagnosticsService.instance.clear()),
              ),
            ],
          ]),
          _section(V5.exportM3u, [
            SwitchListTile(
              title: Text(V5.relativePaths),
              value: _relativeM3u,
              onChanged: (v) => setState(() => _relativeM3u = v),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(V5.exportM3u),
              onTap: () => _exportM3u(lib.songs),
            ),
          ]),
          _section(V5.searchHistory, [
            for (final q in _searchHistory)
              ListTile(title: Text(q)),
            if (_searchHistory.isNotEmpty)
              ListTile(
                title: Text(V5.clearHistory),
                onTap: () => _confirm(
                    V5.clearHistory, V5.clearHistory, SearchHistoryService.clear),
              ),
          ]),
          _section(V5.volumeFilter, [
            DropdownButton<String?>(
              value: _volumeFilter,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem<String?>(
                    value: null, child: Text(V5.all)),
                const DropdownMenuItem<String?>(
                    value: 'internal', child: Text('Internal')),
                const DropdownMenuItem<String?>(
                    value: 'sd', child: Text('SD')),
              ],
              onChanged: (value) async {
                setState(() => _volumeFilter = value);
                await lib.setVolumeFilter(value);
                await _load();
              },
            ),
          ]),
          _section(V5.widgetSettings, [
            Slider(
              value: _queueRows.toDouble(),
              min: 3,
              max: 8,
              divisions: 5,
              label: '$_queueRows',
              onChanged: (v) async {
                setState(() => _queueRows = v.round());
                await WidgetSettingsService.setQueueLength(_queueRows);
              },
            ),
            SwitchListTile(
              title: Text(V5.compactWidget),
              value: _compact,
              onChanged: (v) async {
                setState(() => _compact = v);
                await WidgetSettingsService.setCompact(v);
              },
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(V5.restartForWidget),
            ),
          ]),
        ],
      ),
    );
  }

  bool _relativeM3u = false;

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ...children,
            ],
          ),
        ),
      );

  List<(String, int)> _rowsForFolders(List<Song> songs) {
    final counts = folderCounts(songs);
    final rows = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in rows.take(20)) (e.key, e.value),
    ];
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(text: '$_goalMinutes');
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(V5.goal),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: V5.goalMinutes),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
        ],
      ),
    );
    if (ok != true) return;
    final minutes = int.tryParse(controller.text.trim()) ?? 0;
    await ListeningGoalService.setTargetMinutes(minutes < 0 ? 0 : minutes);
    await _load();
  }

  Future<void> _verifyBackup() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked.isEmpty) return;
      final bytes = await picked.first.readAsBytes();
      if (bytes.length > 32 * 1024 * 1024) return;
      final result = await BackupService.verifyBackupBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
        content: Text(result.songs < 0
            ? V5.backupTooNew
            : V5.verifyResult(
                result.songs, result.playlists, result.lyrics)),
      ));
    } catch (_) {} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportM3u(List<Song> songs) async {
    final l = AppLocalizations.of(context)!;
    if (songs.isEmpty) return;
    final dir = await M3uService.outputDirectory();
    final content = M3uService.buildM3uContent(
      songs,
      relative: _relativeM3u,
      baseDir: dir.path,
    );
    try {
      final file = await M3uService.saveM3uToDownloads('Swara Library', content);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
          SnackBar(content: Text('${V5.m3uSaved}: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${l.error}: $e')));
    }
  }
}
