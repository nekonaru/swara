import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

class SnapshotInfo {
  final String name;
  final DateTime createdAt;
  final int bytes;

  const SnapshotInfo({
    required this.name,
    required this.createdAt,
    required this.bytes,
  });
}

/// Local, app-private snapshots of the same JSON payload used by backup.
/// No network, no cloud, no new permission. At most three files are kept.
class SnapshotService {
  SnapshotService._();
  static final SnapshotService instance = SnapshotService._();

  static const int maxSnapshots = 3;
  static const String snapshotDirName = 'snapshots';
  static const String kLastSnapshotPrefKey = 'backup_last_snapshot_at';
  static const String kAutoRestoreOfferedPrefKey = 'backup_auto_restore_offered';
  static const Duration defaultInterval = Duration(hours: 24);

  Future<SnapshotInfo?>? _creatingValue;
  Future<void> _restoreLock = Future<void>.value();

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$snapshotDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  SnapshotInfo? _parse(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    final match = RegExp(r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})')
        .firstMatch(name);
    if (match == null) return null;
    final createdAt = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
    return SnapshotInfo(name: name, createdAt: createdAt, bytes: file.lengthSync());
  }

  Future<List<SnapshotInfo>> listSnapshots() async {
    final dir = await _dir();
    final out = <SnapshotInfo>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final info = _parse(entity);
      if (info != null) out.add(info);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  static Future<DateTime?> lastSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kLastSnapshotPrefKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> autoRestoreOffered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kAutoRestoreOfferedPrefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markAutoRestoreOffered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kAutoRestoreOfferedPrefKey, true);
    } catch (_) {
      // Best effort.
    }
  }

  Future<SnapshotInfo?> createSnapshot({
    bool force = false,
    Duration minInterval = defaultInterval,
  }) async {
    final existing = _creatingValue;
    if (existing != null) {
      await existing;
      return _lastCreated;
    }
    final completer = Completer<SnapshotInfo?>();
    _creatingValue = completer.future;
    try {
      if (!force) {
        final last = await lastSnapshot();
        if (last != null &&
            DateTime.now().difference(last) < minInterval) {
          completer.complete(null);
          return null;
        }
      }
      final content = await BackupService.exportLibrary();
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final name = 'swara-snapshot-${now.year}${two(now.month)}${two(now.day)}-'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
      final dir = await _dir();
      final temp = File('${dir.path}${Platform.pathSeparator}$name.tmp');
      final finalFile = File('${dir.path}${Platform.pathSeparator}$name');
      await temp.writeAsString(content, flush: true);
      if (await finalFile.exists()) await finalFile.delete();
      await temp.rename(finalFile.path);
      final info = SnapshotInfo(
          name: name, createdAt: now, bytes: finalFile.lengthSync());
      _lastCreated = info;
      final snapshots = await listSnapshots();
      for (final old in snapshots.skip(maxSnapshots)) {
        try {
          final path = '${dir.path}${Platform.pathSeparator}${old.name}';
          if (await File(path).exists()) await File(path).delete();
        } catch (_) {
          // Keep going: a failed prune must not fail the snapshot.
        }
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kLastSnapshotPrefKey, now.toIso8601String());
      } catch (_) {
        // Snapshot itself succeeded.
      }
      completer.complete(info);
      return info;
    } catch (_) {
      completer.complete(null);
      return null;
    } finally {
      _creatingValue = null;
    }
  }

  SnapshotInfo? _lastCreated;

  Future<void> deleteSnapshot(String name) async {
    final dir = await _dir();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (await file.exists()) await file.delete();
  }

  Future<BackupImportResult> restoreSnapshot(String name) async {
    final previous = _restoreLock;
    final release = Completer<void>();
    _restoreLock = release.future;
    await previous.catchError((Object _) {});
    try {
      final dir = await _dir();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      final length = await file.length();
      if (length <= 0 || length > 32 * 1024 * 1024) {
        throw const FormatException('Invalid snapshot: file too large');
      }
      final content = await file.readAsString();
      return await BackupService.importLibrary(content);
    } finally {
      release.complete();
    }
  }
}
