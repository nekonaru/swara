import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';
import 'db_helper.dart';

int _countSnapshotSongs(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final songs = decoded['songs'];
    return songs is List ? songs.length : 0;
  } catch (_) {
    return 0;
  }
}

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

  // Five slots keep a pre-loss snapshot reachable for longer than three.
  static const int maxSnapshots = 5;
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

  /// Song count in the newest snapshot. Used to detect a library that is
  /// much smaller than the last known good state, before a scan rewrites it.
  Future<int> latestSongCount() async {
    final latest = (await listSnapshots()).firstOrNull;
    if (latest == null) return 0;
    try {
      final dir = await _dir();
      final file =
          File('${dir.path}${Platform.pathSeparator}${latest.name}');
      final raw = await file.readAsString();
      return await compute(_countSnapshotSongs, raw);
    } catch (_) {
      return 0;
    }
  }

  Future<SnapshotInfo?> createSnapshot({
    bool force = false,
    Duration minInterval = defaultInterval,
  }) async {
    // Always coalesce, including forced calls: two writers in the same
    // second would otherwise race on the timestamped filename.
    final existing = _creatingValue;
    if (existing != null) {
      await existing;
      // A forced call waits for the in-flight one, then takes its own fresh
      // snapshot instead of returning the automatic one.
      if (!force) return _lastCreated;
    }
    final completer = Completer<SnapshotInfo?>();
    _creatingValue = completer.future;
    try {
      if (!force) {
        final last = await lastSnapshot();
        if (last != null &&
            DateTime.now().difference(last) < minInterval) {
          _lastCreated = null;
          completer.complete(null);
          return null;
        }
      }
      // A fresh install has an empty library. Do not persist and later offer
      // to restore an empty snapshot.
      if (await DBHelper.instance.getSongCount() == 0) {
        _lastCreated = null;
        completer.complete(null);
        return null;
      }
      final previousRestore = _restoreLock;
      await previousRestore.catchError((Object _) {});
      final content = await BackupService.exportLibrary();
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final name = 'swara-snapshot-${now.year}${two(now.month)}${two(now.day)}-'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
      final dir = await _dir();
      final temp = File('${dir.path}${Platform.pathSeparator}'
          '$name.${now.microsecondsSinceEpoch}.tmp');
      final finalFile = File('${dir.path}${Platform.pathSeparator}$name');
      await temp.writeAsString(content, flush: true);
      if (await finalFile.exists()) await finalFile.delete();
      await temp.rename(finalFile.path);
      final info = SnapshotInfo(
          name: name, createdAt: now, bytes: finalFile.lengthSync());
      _lastCreated = info;
      // No automatic rotation. Old snapshots are removed only after an
      // explicit, confirmed action in Settings.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kLastSnapshotPrefKey, now.toIso8601String());
      } catch (_) {
        // Snapshot itself succeeded.
      }
      completer.complete(info);
      return info;
    } catch (_) {
      _lastCreated = null;
      completer.complete(null);
      return null;
    } finally {
      _creatingValue = null;
    }
  }

  SnapshotInfo? _lastCreated;

  /// Snapshots beyond [maxSnapshots] that the user confirmed for removal.
  List<SnapshotInfo> oldSnapshots(List<SnapshotInfo> all) =>
      all.length > maxSnapshots ? all.skip(maxSnapshots).toList() : const [];

  /// Delete only confirmed snapshot names. Unknown names are ignored.
  Future<int> deleteSnapshots(List<String> names) async {
    final dir = await _dir();
    var deleted = 0;
    final pattern = RegExp(r'^swara-snapshot-\d{8}-\d{6}\.json$');
    final known = (await listSnapshots()).map((s) => s.name).toSet();
    for (final name in names) {
      if (!pattern.hasMatch(name) || !known.contains(name)) continue;
      try {
        final file = File('${dir.path}${Platform.pathSeparator}$name');
        if (await file.exists()) {
          await file.delete();
          deleted++;
        }
      } catch (_) {
        // Keep going: one failed delete must not block the rest.
      }
    }
    return deleted;
  }

  /// Read a snapshot without applying it. Used by the restore preview.
  Future<String?> readSnapshot(String name) async {
    if (!RegExp(r'^swara-snapshot-\d{8}-\d{6}\.json$').hasMatch(name)) {
      return null;
    }
    try {
      final dir = await _dir();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteSnapshot(String name) async {
    final valid = RegExp(r'^swara-snapshot-\d{8}-\d{6}\.json$')
        .hasMatch(name);
    if (!valid) return;
    final known = (await listSnapshots()).any((s) => s.name == name);
    if (!known) return;
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
