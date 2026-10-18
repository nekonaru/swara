import 'dart:convert';
import 'dart:io';

import '../services/db_helper.dart';

// Backup format version. Bump when the JSON schema changes.
const int kBackupFormatVersion = 1;

// Summary of an import operation. Counts only rows actually restored.
class BackupImportResult {
  final int playlistsCreated;
  final int playlistMembersAdded;
  final int favoritesRestored;
  final int listeningEntriesRestored;

  const BackupImportResult({
    this.playlistsCreated = 0,
    this.playlistMembersAdded = 0,
    this.favoritesRestored = 0,
    this.listeningEntriesRestored = 0,
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

  // Collect playlists with members, favorite ids, and listening
  // entries into a single JSON string.
  static Future<String> exportLibrary() async {
    final dbHelper = DBHelper.instance;

    // Playlists plus their member song ids.
    final playlistRows = await dbHelper.getPlaylists();
    final List<Map<String, dynamic>> playlistsJson = [];
    for (final row in playlistRows) {
      final id = row['id'] as int?;
      final name = (row['name'] ?? '').toString();
      if (id == null || name.isEmpty) continue;
      List<int> memberIds = [];
      try {
        final members = await dbHelper.getSongsInPlaylist(id);
        memberIds = members.map((s) => s.id).toList();
      } catch (_) {
        // Keep the playlist shell even when member read fails.
        memberIds = [];
      }
      playlistsJson.add({'name': name, 'songIds': memberIds});
    }

    // Favorite song ids.
    List<int> favoriteIds = [];
    try {
      final favs = await dbHelper.getFavorites();
      favoriteIds = favs.map((s) => s.id).toList();
    } catch (_) {
      favoriteIds = [];
    }

    // Listening history rows via the existing db getter.
    List<Map<String, dynamic>> entriesJson = [];
    try {
      final database = await dbHelper.db;
      final rows = await database.rawQuery(
        'SELECT songId, timestamp, listenedMs FROM listening_entries ORDER BY timestamp ASC',
      );
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

    final payload = {
      'version': kBackupFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'playlists': playlistsJson,
      'favorites': favoriteIds,
      'listening_entries': entriesJson,
    };
    return jsonEncode(payload);
  }

  // Validate the JSON structure and write it back with a replace-safe
  // additive strategy. Each section is guarded by try/catch so one
  // bad section does not abort the others.
  static Future<BackupImportResult> importLibrary(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup: root must be an object');
    }
    final playlistsRaw = decoded['playlists'];
    final favoritesRaw = decoded['favorites'];
    final entriesRaw = decoded['listening_entries'];
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

    final dbHelper = DBHelper.instance;

    // Section 1: playlists. Create by name when missing, then add
    // member song ids that exist in the songs table and are not
    // already in the playlist.
    try {
      final existingRows = await dbHelper.getPlaylists();
      final Map<String, int> idByName = {};
      for (final r in existingRows) {
        final name = (r['name'] ?? '').toString();
        final id = r['id'] as int?;
        if (name.isNotEmpty && id != null) idByName[name] = id;
      }
      final database = await dbHelper.db;
      for (final item in (playlistsRaw as List? ?? [])) {
        try {
          if (item is! Map) continue;
          final name = (item['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final rawIds = item['songIds'];
          if (rawIds != null && rawIds is! List) continue;
          int playlistId;
          if (idByName.containsKey(name)) {
            playlistId = idByName[name]!;
          } else {
            playlistId = await dbHelper.createPlaylist(name);
            idByName[name] = playlistId;
            playlistsCreated++;
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
            // Only link songs that still exist in the library.
            final placeholders = List.filled(candidates.length, '?').join(',');
            final found = await database.rawQuery(
              'SELECT id FROM songs WHERE id IN ($placeholders)',
              candidates,
            );
            final existingIds =
                found.map((r) => r['id']).whereType<int>().toSet();
            final insertable =
                candidates.where((id) => existingIds.contains(id)).toList();
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
    // when the song still exists.
    try {
      final database = await dbHelper.db;
      for (final rawId in (favoritesRaw as List? ?? [])) {
        try {
          final songId = (rawId as num?)?.toInt();
          if (songId == null) continue;
          final found = await database.query('songs',
              columns: ['id'],
              where: 'id = ?',
              whereArgs: [songId],
              limit: 1);
          if (found.isEmpty) continue;
          await dbHelper.setFavorite(songId, true);
          favoritesRestored++;
        } catch (_) {
          continue;
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
      // Preload existing triples so re-imports skip rows that are
      // already stored (dedup on songId + timestamp + listenedMs).
      final Set<String> existingTriples = {};
      try {
        final existing = await database.query('listening_entries',
            columns: ['songId', 'timestamp', 'listenedMs']);
        for (final r in existing) {
          existingTriples.add(
              '${r['songId']}|${r['timestamp']}|${r['listenedMs']}');
        }
      } catch (_) {
        // When the preload fails, fall back to inserting validated rows.
      }
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
          if (existingTriples.contains(triple)) continue;
          // Skip entries pointing at songs that no longer exist.
          final found = await database.query('songs',
              columns: ['id'],
              where: 'id = ?',
              whereArgs: [songId],
              limit: 1);
          if (found.isEmpty) continue;
          await database.insert('listening_entries', {
            'songId': songId,
            'timestamp': tsRaw,
            'listenedMs': listenedMs,
          });
          existingTriples.add(triple);
          entriesRestored++;
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // Keep earlier sections even if history fails.
    }

    if (playlistsCreated == 0 &&
        membersAdded == 0 &&
        favoritesRestored == 0 &&
        entriesRestored == 0) {
      // Still a valid file shape, but nothing could be restored.
      // Throw so the UI can tell empty/incompatible apart from success.
      final hasAnyData = ((playlistsRaw as List? ?? []).isNotEmpty) ||
          ((favoritesRaw as List? ?? []).isNotEmpty) ||
          ((entriesRaw as List? ?? []).isNotEmpty);
      if (hasAnyData) {
        throw const FormatException(
            'Backup contains no entries matching this library');
      }
    }

    return BackupImportResult(
      playlistsCreated: playlistsCreated,
      playlistMembersAdded: membersAdded,
      favoritesRestored: favoritesRestored,
      listeningEntriesRestored: entriesRestored,
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
    } catch (_) {
      // Report partial progress instead of throwing.
    }
    return deleted;
  }
}
