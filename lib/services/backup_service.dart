import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/language_provider.dart';
import '../services/art_cache_service.dart';
import '../services/embedded_art_service.dart';
import '../utils/backup_settings_codec.dart';

import '../services/db_helper.dart';
import 'player_service.dart';

// Backup format version. Bump when the JSON schema changes.
const int kBackupFormatVersion = 2;

// Decode the backup payload off the main isolate; the import can be a
// multi-megabyte JSON document and the parse must not block the UI.
Map<String, dynamic> _decodeBackup(String rawJson) {
  final decoded = jsonDecode(rawJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid backup: root must be an object');
  }
  return decoded;
}

// Encode the export payload off the main isolate as well.
String _encodeBackup(Map<String, dynamic> payload) => jsonEncode(payload);

// Summary of an import operation. Counts only rows actually restored.
class BackupImportResult {
  final int playlistsCreated;
  final int playlistMembersAdded;
  final int favoritesRestored;
  final int listeningEntriesRestored;
  // Rows whose source songs do not exist in this library (unrestorable).
  final int listeningEntriesSkipped;
  final int playlistMembersSkipped;
  final int favoritesSkipped;
  final int preferencesRestored;
  final int songSettingsRestored;
  final int folderSettingsRestored;

  const BackupImportResult({
    this.playlistsCreated = 0,
    this.playlistMembersAdded = 0,
    this.favoritesRestored = 0,
    this.listeningEntriesRestored = 0,
    this.listeningEntriesSkipped = 0,
    this.playlistMembersSkipped = 0,
    this.favoritesSkipped = 0,
    this.preferencesRestored = 0,
    this.songSettingsRestored = 0,
    this.folderSettingsRestored = 0,
  });
}

// Simple usage stats for cached album art files.
class ArtCacheUsage {
  final int bytes;
  final int files;
  const ArtCacheUsage({this.bytes = 0, this.files = 0});
}

// Export/import of user library data as a JSON string.
// Uses only the existing DBHelper API plus the raw db getter for
// the listening_entries table which has no dedicated list method.
// Strategy on import is additive: only missing rows are added,
// existing data is never deleted.
class BackupService {
  BackupService._();

  // Preference keys carried by a backup. Whitelisted so a future sensitive
  // preference is never exported accidentally.
  static const List<String> kBackupPrefKeys = [
    'equalizerPreset',
    'custom_eq_gains',
    'custom_eq_presets',
    'textScale',
    'themeMode',
    'accentColorIndex',
    'amoledBlack',
    'dynamicColor',
    'loudness_enabled',
    'crossfadeSeconds',
    'crossfadeEnabled',
    'smartShuffle',
    'playbackSpeed',
    'playbackPitch',
    'sleepScheduleEnabled',
    'sleepScheduleHour',
    'sleepScheduleMinute',
    'shuffle',
    'repeatMode',
  ];

  // Collect playlists with members, favorite ids, and listening
  // entries into a single JSON string.
  // The reads run inside one transaction so the exported snapshot is
  // consistent: writes cannot interleave between the favorites read and
  // the history read.
  static Future<String> exportLibrary() async {
    // Preferences are bundled so a reinstall can restore the user's tunings
    // (EQ curves, crossfade, speeds, theme) along with the library data.
    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};
    for (final key in kBackupPrefKeys) {
      if (!prefs.containsKey(key)) continue;
      final value = prefs.get(key);
      if (value is String || value is bool || value is num || value is List<String>) {
        settings[key] = value;
      }
    }
    settings['language_code'] = LanguageProvider.instance.locale.languageCode;
    final dbHelper = DBHelper.instance;
    final database = await dbHelper.db;
    final snapshot = await database.transaction((txn) async {
      // Playlists plus their member song ids.
      final playlistRows =
          await txn.query('playlists', orderBy: 'createdAt DESC');
      final List<Map<String, dynamic>> playlistsJson = [];
      for (final row in playlistRows) {
        final id = row['id'] as int?;
        final name = (row['name'] ?? '').toString();
        if (id == null || name.isEmpty) continue;
        List<int> memberIds = [];
        try {
          final memberRows = await txn.rawQuery(
            'SELECT ps.songId FROM playlist_songs ps '
            'WHERE ps.playlistId = ? '
            'ORDER BY ps.position ASC, ps.addedAt ASC',
            [id],
          );
          memberIds = memberRows.map((r) => r['songId'] as int).toList();
        } catch (_) {
          // Keep the playlist shell even when member read fails.
          memberIds = [];
        }
        playlistsJson.add({
          'name': name,
          'songIds': memberIds,
          'folder': (row['folder'] ?? '').toString(),
          'createdAt': (row['createdAt'] ?? '').toString(),
        });
      }

      // Favorite song ids.
      List<int> favoriteIds = [];
      try {
        final favRows = await txn.query('songs',
            columns: ['id'], where: 'isFavorite = 1', orderBy: 'title ASC');
        favoriteIds = favRows.map((r) => r['id'] as int).toList();
      } catch (_) {
        favoriteIds = [];
      }

      // Listening history rows.
      List<Map<String, dynamic>> entriesJson = [];
      try {
        final rows = await txn.rawQuery('SELECT songId, timestamp, listenedMs '
            'FROM listening_entries ORDER BY timestamp ASC');
        entriesJson = rows
            .map((r) => {
                  'songId': r['songId'],
                  'timestamp': r['timestamp'],
                  'listenedMs': r['listenedMs'],
                })
            .toList();
      } catch (_) {
        entriesJson = [];
      }

      return (playlistsJson, favoriteIds, entriesJson);
    });
    final playlistsJson = snapshot.$1;
    final favoriteIds = snapshot.$2;
    final entriesJson = snapshot.$3;

    final songSettings = await DBHelper.instance.getAllSongPlaybackSettings();
    final folderSettings = await DBHelper.instance.getAllFolderPlaybackSettings();
    final payload = {
      'version': kBackupFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'playlists': playlistsJson,
      'favorites': favoriteIds,
      'listening_entries': entriesJson,
      'settings': settings,
      'playback_settings': {
        'songs': songSettings.entries.map((e) => {
          'songId': e.key,
          'gainDb': e.value['gainDb'],
          'skipStartMs': e.value['skipStartMs'],
          'skipEndMs': e.value['skipEndMs'],
        }).toList(),
        'folders': folderSettings.entries.map((e) => {
          'folderPath': e.key,
          'gainDb': e.value['gainDb'],
          'skipStartMs': e.value['skipStartMs'],
          'skipEndMs': e.value['skipEndMs'],
        }).toList(),
      },
    };
    return compute(_encodeBackup, payload);
  }

  static const String kLastExportPrefKey = 'backup_last_export_at';

  /// Remember a successful export so Settings can show the last time the
  /// library was backed up. Best effort only.
  static Future<void> recordExport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          kLastExportPrefKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Export itself already succeeded; a prefs failure is not fatal.
    }
  }

  static Future<DateTime?> lastExport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kLastExportPrefKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  // Write the backup JSON to the Downloads folder (falling back to external
  // storage or the temp dir) and return the file. The name carries a
  // timestamp so repeated exports never overwrite each other.
  static Future<File> saveBackupToFile(String content) async {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }
    if (dir == null) {
      try {
        dir = await getExternalStorageDirectory();
      } catch (_) {
        dir = null;
      }
    }
    dir ??= await getTemporaryDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final file =
        File('${dir.path}${Platform.pathSeparator}swara-backup-$stamp.json');
    await file.writeAsString(content, flush: true);
    return file;
  }

  // Validate the JSON structure and write it back with a replace-safe
  // additive strategy. Each section is guarded by try/catch so one
  // bad section does not abort the others.
  static Future<BackupImportResult> importLibrary(String rawJson) async {
    final decoded = await compute(_decodeBackup, rawJson);
    // Reject backups from a newer format instead of silently restoring a
    // shape this build does not understand.
    final versionRaw = decoded['version'];
    if (versionRaw != null) {
      final version = versionRaw is num ? versionRaw.toInt() : -1;
      // Older backups remain importable; only a NEWER format must be rejected.
      if (version > kBackupFormatVersion) {
        throw FormatException(
            'Unsupported backup version: $versionRaw (expected $kBackupFormatVersion)');
      }
    }
    final playlistsRaw = decoded['playlists'];
    final favoritesRaw = decoded['favorites'];
    final entriesRaw = decoded['listening_entries'];
    final settingsRaw = decoded['settings'];
    final playbackRaw = decoded['playback_settings'];
    if (playbackRaw != null && playbackRaw is! Map) {
      throw const FormatException('Invalid backup: playback_settings must be an object');
    }
    final songsPlaybackRaw = playbackRaw is Map ? playbackRaw['songs'] : null;
    final foldersPlaybackRaw = playbackRaw is Map ? playbackRaw['folders'] : null;
    if (songsPlaybackRaw != null && songsPlaybackRaw is! List) {
      throw const FormatException('Invalid backup: song settings must be a list');
    }
    if (foldersPlaybackRaw != null && foldersPlaybackRaw is! List) {
      throw const FormatException('Invalid backup: folder settings must be a list');
    }
    if (settingsRaw != null && settingsRaw is! Map) {
      throw const FormatException('Invalid backup: settings must be an object');
    }
    if (playlistsRaw != null && playlistsRaw is! List) {
      throw const FormatException('Invalid backup: playlists must be a list');
    }
    if (favoritesRaw != null && favoritesRaw is! List) {
      throw const FormatException('Invalid backup: favorites must be a list');
    }
    if (entriesRaw != null && entriesRaw is! List) {
      throw const FormatException(
          'Invalid backup: listening_entries must be a list');
    }

    int playlistsCreated = 0;
    int membersAdded = 0;
    int favoritesRestored = 0;
    int entriesRestored = 0;
    int entriesSkipped = 0;
    int membersSkipped = 0;
    int favoritesSkipped = 0;

    final dbHelper = DBHelper.instance;

    // Section 1: playlists. Create by name when missing, then add
    // member song ids that exist in the songs table and are not
    // already in the playlist.
    try {
      final existingRows = await dbHelper.getPlaylists();
      final Map<String, int> idByName = {};
      final Map<String, String> folderByName = {};
      for (final r in existingRows) {
        final name = (r['name'] ?? '').toString();
        final id = r['id'] as int?;
        if (name.isNotEmpty && id != null) {
          idByName[name] = id;
          folderByName[name] = (r['folder'] ?? '').toString().trim();
        }
      }
      final database = await dbHelper.db;
      for (final item in (playlistsRaw as List? ?? [])) {
        try {
          if (item is! Map) continue;
          final name = (item['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final rawIds = item['songIds'];
          if (rawIds != null && rawIds is! List) continue;
          final itemCreatedAt = (item['createdAt'] ?? '').toString().trim();
          final createdAt = DateTime.tryParse(itemCreatedAt)?.toIso8601String();
          final isNew = !idByName.containsKey(name);
          int playlistId;
          if (!isNew) {
            playlistId = idByName[name]!;
          } else if (createdAt != null) {
            // Preserve the original ordering: insert with the export's
            // timestamp instead of "now".
            playlistId = await dbHelper.createPlaylistWithDate(name, createdAt);
            idByName[name] = playlistId;
            playlistsCreated++;
          } else {
            playlistId = await dbHelper.createPlaylist(name);
            idByName[name] = playlistId;
            playlistsCreated++;
          }
          // Restore the folder label only when the playlist did not exist
          // before (folders always come from the backup) or when the local
          // playlist is ungrouped; an existing grouping is never stomped.
          try {
            final folder = (item['folder'] ?? '').toString().trim();
            final localFolder = folderByName[name] ?? '';
            if (folder.isNotEmpty && (isNew || localFolder.isEmpty)) {
              await dbHelper.setPlaylistFolder(playlistId, folder);
              folderByName[name] = folder;
            }
          } catch (_) {
            // Folder label is optional metadata; never block a restore.
          }
          final current = await dbHelper.getSongsInPlaylist(playlistId);
          final currentIds = current.map((s) => s.id).toSet();
          // Collect the candidates first, then check existence with one query
          // and insert with one transaction. The per member path asked the
          // songs table for every id and inserted row by row, which turned a
          // large playlist restore into thousands of round trips.
          final candidates = <int>[];
          for (final rawId in (rawIds as List? ?? [])) {
            try {
              final songId = (rawId as num?)?.toInt();
              if (songId == null || currentIds.contains(songId)) continue;
              currentIds.add(songId);
              candidates.add(songId);
            } catch (_) {
              // Skip a bad member row.
              continue;
            }
          }
          if (candidates.isNotEmpty) {
            // Only link songs that still exist in the library. Chunked so a
            // large backup stays below SQLITE_MAX_VARIABLE_NUMBER on older
            // Android (SQLite before 3.32 allows 999 variables).
            final existingIds = <int>{};
            const chunk = 400;
            for (var off = 0; off < candidates.length; off += chunk) {
              final end = off + chunk > candidates.length ? candidates.length : off + chunk;
              final slice = candidates.sublist(off, end);
              final placeholders = List.filled(slice.length, '?').join(',');
              final found = await database.rawQuery(
                'SELECT id FROM songs WHERE id IN ($placeholders)',
                slice,
              );
              existingIds.addAll(found.map((r) => r['id']).whereType<int>());
            }
            final insertable =
                candidates.where((id) => existingIds.contains(id)).toList();
            // Candidate ids whose songs no longer exist in this library used
            // to vanish silently; count them now for the summary.
            membersSkipped += candidates.toSet().difference(existingIds).length;
            if (insertable.isNotEmpty) {
              membersAdded += await dbHelper.addSongsToPlaylist(
                playlistId,
                insertable,
              );
            }
          }
        } catch (_) {
          // Skip single bad playlist entries.
          continue;
        }
      }
    } catch (e) {
      // When the whole playlist section fails, keep other sections alive
      // but surface the failure when nothing else was restored either.
      if (playlistsCreated == 0 && membersAdded == 0) {
        // Fall through to remaining sections; validation of at least
        // one usable section happens at the end.
      }
    }

    // Section 2: favorites. Mark each listed song id as favorite
    // when the song still exists. Existence is checked with chunked IN
    // queries instead of one query per id.
    try {
      final database = await dbHelper.db;
      final candidates = <int>[];
      final seen = <int>{};
      for (final rawId in (favoritesRaw as List? ?? [])) {
        try {
          final songId = (rawId as num?)?.toInt();
          if (songId == null) continue;
          if (seen.add(songId)) candidates.add(songId);
        } catch (_) {
          continue;
        }
      }
      if (candidates.isNotEmpty) {
        final existingIds = <int>{};
        // Stay well below SQLITE_MAX_VARIABLE_NUMBER.
        const chunk = 400;
        for (var off = 0; off < candidates.length; off += chunk) {
          final end = off + chunk > candidates.length ? candidates.length : off + chunk;
          final slice = candidates.sublist(off, end);
          final placeholders = List.filled(slice.length, '?').join(',');
          final found = await database.rawQuery(
            'SELECT id FROM songs WHERE id IN ($placeholders)',
            slice,
          );
          existingIds.addAll(found.map((r) => r['id']).whereType<int>());
        }
        // Candidate favorite ids whose songs are gone; count them rather than
        // silently dropping them.
        favoritesSkipped = candidates.toSet().difference(existingIds).length;
        for (final songId in existingIds) {
          try {
            await dbHelper.setFavorite(songId, true);
            favoritesRestored++;
          } catch (_) {
            continue;
          }
        }
      }
    } catch (_) {
      // Keep playlist and history results even if favorites fail.
    }

    // Section 3: listening history. Re-insert validated rows with
    // fresh row ids so imports never collide on primary keys.
    // Note: song ids are local MediaStore ids which are not stable
    // across devices, so a restore on a different phone only matches
    // when the ids happen to be the same. Rows pointing at missing
    // songs are skipped.
    try {
      final database = await dbHelper.db;
      // Validate every candidate row (parse, clamp) first. The triple
      // existence snapshot is taken inside the transaction below so two
      // concurrent imports cannot both pass the dedup check and double the
      // history.
      final parsedEntries = <Map<String, dynamic>>[];
      final seenTriples = <String>{};
      final entrySongIds = <int>{};
      for (final item in (entriesRaw as List? ?? [])) {
        try {
          if (item is! Map) continue;
          final songId =
              (item['songId'] is num) ? (item['songId'] as num).toInt() : null;
          var listenedMs = (item['listenedMs'] is num)
              ? (item['listenedMs'] as num).toInt()
              : null;
          final tsRaw = item['timestamp']?.toString() ?? '';
          if (songId == null || listenedMs == null || tsRaw.isEmpty) continue;
          if (DateTime.tryParse(tsRaw) == null) continue;
          // Clamp to a sane single-session range (0 to 24h in ms) so
          // corrupt or negative values cannot skew stats.
          listenedMs = listenedMs.clamp(0, 86400000);
          final triple = '$songId|$tsRaw|$listenedMs';
          if (!seenTriples.add(triple)) continue;
          parsedEntries.add({
            'songId': songId,
            'timestamp': tsRaw,
            'listenedMs': listenedMs,
            'triple': triple,
          });
          entrySongIds.add(songId);
        } catch (_) {
          continue;
        }
      }
      final existingEntrySongIds = <int>{};
      const chunk = 400;
      final entryIdList = entrySongIds.toList();
      for (var off = 0; off < entryIdList.length; off += chunk) {
        final end = off + chunk > entryIdList.length ? entryIdList.length : off + chunk;
        final slice = entryIdList.sublist(off, end);
        final placeholders = List.filled(slice.length, '?').join(',');
        final found = await database.rawQuery(
          'SELECT id FROM songs WHERE id IN ($placeholders)',
          slice,
        );
        existingEntrySongIds.addAll(found.map((r) => r['id']).whereType<int>());
      }
      // The whole insert runs inside one transaction, and the dedup snapshot
      // is taken there, so two concurrent imports cannot both pass the check
      // and double the history. Rows are inserted with fresh ids on purpose.
      final transactionResult = await database.transaction((txn) async {
        final existingTriples = <String>{};
        try {
          final existing = await txn.query(
              'listening_entries',
              columns: ['songId', 'timestamp', 'listenedMs']);
          for (final r in existing) {
            existingTriples.add(
                '${r['songId']}|${r['timestamp']}|${r['listenedMs']}');
          }
        } catch (_) {
          // Fall back to inserting validated rows when the snapshot fails.
        }
        var restored = 0;
        var skipped = 0;
        for (final entry in parsedEntries) {
          try {
            // Skip entries pointing at songs that no longer exist.
            if (!existingEntrySongIds.contains(entry['songId'])) {
              skipped++;
              continue;
            }
            final triple = entry['triple'] as String;
            if (existingTriples.contains(triple)) continue;
            await txn.insert('listening_entries', {
              'songId': entry['songId'],
              'timestamp': entry['timestamp'],
              'listenedMs': entry['listenedMs'],
            });
            existingTriples.add(triple);
            restored++;
          } catch (_) {
            skipped++;
            continue;
          }
        }
        return (restored, skipped);
      });
      entriesRestored += transactionResult.$1;
      entriesSkipped += transactionResult.$2;
    } catch (_) {
      // Keep earlier sections even if history fails.
    }

    if (playlistsCreated == 0 &&
        membersAdded == 0 &&
        favoritesRestored == 0 &&
        entriesRestored == 0 &&
        membersSkipped == 0 &&
        favoritesSkipped == 0 &&
        entriesSkipped == 0) {
      // Still a valid file shape, but nothing could be restored either.
      // Throw so the UI can tell empty/incompatible apart from success.
      final hasAnyData = ((playlistsRaw as List? ?? []).isNotEmpty) ||
          ((favoritesRaw as List? ?? []).isNotEmpty) ||
          ((entriesRaw as List? ?? []).isNotEmpty);
      if (hasAnyData) {
        throw const FormatException(
            'Backup contains no entries matching this library');
      }
    }

    // Playback overrides are additive: existing local settings always win.
    var songSettingsRestored = 0;
    var folderSettingsRestored = 0;
    try {
      final existingSongs =
          await DBHelper.instance.getAllSongPlaybackSettings();
      for (final raw in (songsPlaybackRaw as List? ?? [])) {
        if (raw is! Map) continue;
        final id = (raw['songId'] as num?)?.toInt();
        if (id == null || existingSongs.containsKey(id)) continue;
        await DBHelper.instance.setSongPlaybackSettings(
          id,
          gainDb: (raw['gainDb'] as num?)?.toDouble() ?? 0,
          skipStartMs: (raw['skipStartMs'] as num?)?.toInt() ?? 0,
          skipEndMs: (raw['skipEndMs'] as num?)?.toInt() ?? 0,
        );
        existingSongs[id] = const {};
        songSettingsRestored++;
      }
      final existingFolders =
          await DBHelper.instance.getAllFolderPlaybackSettings();
      for (final raw in (foldersPlaybackRaw as List? ?? [])) {
        if (raw is! Map) continue;
        final path = raw['folderPath'] as String?;
        if (path == null || path.isEmpty || existingFolders.containsKey(path)) {
          continue;
        }
        await DBHelper.instance.setFolderPlaybackSettings(
          path,
          gainDb: (raw['gainDb'] as num?)?.toDouble() ?? 0,
          skipStartMs: (raw['skipStartMs'] as num?)?.toInt() ?? 0,
          skipEndMs: (raw['skipEndMs'] as num?)?.toInt() ?? 0,
        );
        existingFolders[path] = const {};
        folderSettingsRestored++;
      }
      await PlayerService.instance.refreshPlaybackSettings();
    } catch (_) {
      // A bad override must not fail the whole restore.
    }

    // Preferences are additive: only keys the user has never set are filled
    // from a backup, so a restore cannot stomp current choices.
    var preferencesRestored = 0;
    if (settingsRaw != null) {
      try {
        final settings = decodeBackupSettings(settingsRaw);
        final prefs = await SharedPreferences.getInstance();
        for (final entry in settings.entries) {
          if (prefs.containsKey(entry.key)) continue;
          final value = entry.value;
          if (value is String) {
            await prefs.setString(entry.key, value);
          } else if (value is bool) {
            await prefs.setBool(entry.key, value);
          } else if (value is int) {
            await prefs.setInt(entry.key, value);
          } else if (value is double) {
            await prefs.setDouble(entry.key, value);
          } else if (value is List<String>) {
            await prefs.setStringList(entry.key, value);
          } else {
            continue;
          }
          preferencesRestored++;
        }
      } catch (_) {
        // A bad settings section must never fail the library restore.
      }
    }

    // A restore changed the listening history, so the dashboard aggregate
    // cache must not survive to show pre-restore numbers.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('dashboard_aggregate_cache_v1');
    } catch (_) {
      // Best effort: the numbers self-heal on the next full reload.
    }

    return BackupImportResult(
      playlistsCreated: playlistsCreated,
      playlistMembersAdded: membersAdded,
      favoritesRestored: favoritesRestored,
      listeningEntriesRestored: entriesRestored,
      listeningEntriesSkipped: entriesSkipped,
      playlistMembersSkipped: membersSkipped,
      favoritesSkipped: favoritesSkipped,
      preferencesRestored: preferencesRestored,
      songSettingsRestored: songSettingsRestored,
      folderSettingsRestored: folderSettingsRestored,
    );
  }

  // Total bytes and file count of album art files referenced by songs.
  static Future<ArtCacheUsage> artCacheUsage() async {
    int bytes = 0;
    int files = 0;
    try {
      final songs = await DBHelper.instance.getAllSongs();
      final seen = <String>{};
      for (final s in songs) {
        final path = s.albumArtPath;
        if (path == null || path.isEmpty || !seen.add(path)) continue;
        try {
          final f = File(path);
          if (await f.exists()) {
            bytes += await f.length();
            files++;
          }
        } catch (_) {
          // Single unreadable file must not break the total.
          continue;
        }
      }
      // Include the extracted embedded covers and the remote cover cache.
      bytes += await EmbeddedArtService.totalBytes();
      files += await EmbeddedArtService.totalFiles();
      final remote = await ArtCacheService.instance.usage();
      bytes += remote.bytes.round();
      files += remote.files;
    } catch (_) {
      // On DB failure report an empty cache rather than throwing.
    }
    return ArtCacheUsage(bytes: bytes, files: files);
  }

  // Delete cached art files and clear albumArtPath in the DB.
  // Returns the number of files actually deleted.
  static Future<int> clearArtCache() async {
    int deleted = 0;
    try {
      final songs = await DBHelper.instance.getAllSongs();
      final seen = <String>{};
      for (final s in songs) {
        final path = s.albumArtPath;
        if (path == null || path.isEmpty || !seen.add(path)) continue;
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
            deleted++;
          }
        } catch (_) {
          // Keep going when one file cannot be deleted.
          continue;
        }
      }
      // Null out references using the existing db getter.
      try {
        final database = await DBHelper.instance.db;
        await database.update('songs', {'albumArtPath': null},
            where: 'albumArtPath IS NOT NULL');
      } catch (_) {
        // File deletion already done; DB null-out is best effort here.
      }
      // Also drop the extracted embedded covers and the remote cover cache
      // (files, memory indexes and the image cache), so covers do not come
      // straight back after a "clear".
      deleted += await EmbeddedArtService.clearCache();
      await ArtCacheService.instance.clearAll();
      // Nudge every listener so the in-memory queue snapshots and the home
      // widget both forget the deleted art immediately.
      PlayerService.instance.rebroadcastState();
    } catch (_) {
      // Report partial progress instead of throwing.
    }
    return deleted;
  }
}
