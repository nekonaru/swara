import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../utils/backup_paths.dart';
import '../providers/language_provider.dart';
import '../services/art_cache_service.dart';
import '../services/embedded_art_service.dart';
import '../utils/backup_settings_codec.dart';

import '../services/db_helper.dart';
import 'player_service.dart';
import 'smart_playlist_service.dart';

// Backup format version. Bump when the JSON schema changes.
const int kBackupFormatVersion = 3;
const int kDurationToleranceMs = 1000;

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

/// Canonical path key for cross-device matching. IDs from MediaStore are not
/// stable, so the path (with a basename + duration fallback) is the identity.
String backupBasename(String raw) {
  final normalized = normalizeBackupPath(raw);
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

String backupFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'swara-backup-${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
}

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
  final int songsMatched;
  final int songsUnmatched;
  final int metadataRestored;
  final int lyricsRestored;
  final int syncedLyricsRestored;
  final int lyricOffsetsRestored;
  final int bookmarksRestored;
  final int bookmarksSkipped;

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
    this.songsMatched = 0,
    this.songsUnmatched = 0,
    this.metadataRestored = 0,
    this.lyricsRestored = 0,
    this.syncedLyricsRestored = 0,
    this.lyricOffsetsRestored = 0,
    this.bookmarksRestored = 0,
    this.bookmarksSkipped = 0,
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
          'rule': (row['rule'] ?? '').toString(),
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

    // v3 identity: stable path plus a basename + duration fallback. MediaStore
    // ids stay in the file for v2 readers but are never trusted by v3.
    final identityRows = await DBHelper.instance.getSongIdentityRows();
    final identityById = <int, Map<String, Object?>>{
      for (final row in identityRows) (row['id'] as int): row,
    };
    String identityKeyFor(int id) =>
        normalizeBackupPath((identityById[id]?['filePath'] as String?) ?? '');
    String basenameFor(int id) =>
        backupBasename((identityById[id]?['filePath'] as String?) ?? '');
    int durationFor(int id) =>
        (identityById[id]?['durationMs'] as num?)?.toInt() ?? 0;

    for (final playlist in playlistsJson) {
      final ids = (playlist['songIds'] as List?) ?? const <int>[];
      playlist['memberIdentities'] = [
        for (final id in ids) identityKeyFor(id as int),
      ];
    }
    for (final entry in entriesJson) {
      entry['identityKey'] = identityKeyFor((entry['songId'] as num).toInt());
    }

    final allSongs = await DBHelper.instance.getAllSongs();
    final aliasById = await DBHelper.instance.getPathAliases();
    final songExtras = await DBHelper.instance
        .getBackupSongExtras(allSongs.map((s) => s.id).toList());
    final songsJson = <Map<String, dynamic>>[];
    for (final song in allSongs) {
      final extras = songExtras[song.id] ?? const <String, Object?>{};
      final lrc = extras['lrc'] as String?;
      final offset = (extras['offsetMs'] as num?)?.toInt() ?? 0;
      final bookmarks = (extras['bookmarks'] as List<Object?>?) ?? const [];
      songsJson.add({
        'identityKey': identityKeyFor(song.id),
        'aliases': aliasById[song.id] ?? <String>[],
        'filePath': song.filePath,
        'basename': basenameFor(song.id),
        'durationMs': durationFor(song.id),
        'legacySongId': song.id,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'genre': song.genre,
        'region': song.region,
        'lyrics': song.lyrics,
        'metadataScanned': song.metadataScanned,
        'syncedLyrics': lrc,
        'lyricOffsetMs': offset,
        'bookmarks': [
          for (final b in bookmarks)
            if (b is Map<String, Object?>)
              {
                'positionMs': b['positionMs'],
                'label': b['label'],
                'createdAt': b['createdAt'],
              },
        ],
        'isFavorite': song.isFavorite,
      });
    }

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
          'identityKey': identityKeyFor(e.key),
          'filePath': (identityById[e.key]?['filePath'] as String?) ?? '',
          'basename': basenameFor(e.key),
          'durationMs': durationFor(e.key),
          'gainDb': e.value['gainDb'],
          'skipStartMs': e.value['skipStartMs'],
          'skipEndMs': e.value['skipEndMs'],
        }).toList(),
        'folders': folderSettings.entries.map((e) => {
          'folderPath': e.key,
          'folderKey': normalizeBackupPath(e.key),
          'gainDb': e.value['gainDb'],
          'skipStartMs': e.value['skipStartMs'],
          'skipEndMs': e.value['skipEndMs'],
        }).toList(),
      },
    };
    final identityAliases = <String, String>{};
    for (final song in allSongs) {
      final current = identityKeyFor(song.id);
      for (final alias in aliasById[song.id] ?? const <String>[]) {
        identityAliases[alias] = current;
      }
    }
    payload['identityAliases'] = identityAliases;
    payload['songs'] = songsJson;
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

  // Ask the system file picker where to save the backup. The old
  // getDownloadsDirectory() path was app-private on Android and invisible in
  // the Files app. SAF needs no manifest change and no new permission.
  // Returns null when the user cancels, otherwise the chosen file name.
  static Future<String?> saveBackupToFile(String content,
      {String? fileName}) async {
    final name = fileName ?? backupFileName(DateTime.now());
    final uri = await FilePicker.saveFile(
      fileName: name,
      bytes: utf8.encode(content),
      mimeType: 'application/json',
    );
    // Android may hand back a content:// document URI with no usable path.
    // Show the chosen name rather than a misleading filesystem path.
    return uri == null ? null : name;
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
    var favoritesRaw = decoded['favorites'];
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

    // v3 identity remapping. MediaStore ids are not stable across devices,
    // so translate every id-bearing v3 list to the local ids resolved from a
    // normalized path, with a basename + duration fallback. The v2 id paths
    // below then work unchanged on the corrected ids.
    final resolvedV3Songs = <(int id, Map<String, dynamic> raw)>[];
    final versionNumber = versionRaw is num ? versionRaw.toInt() : 0;
    if (versionNumber >= 3) {
      final songsRaw = decoded['songs'];
      if (songsRaw is! List) {
        throw const FormatException('Invalid backup: songs must be a list');
      }
      final localIdentityRows = await DBHelper.instance.getSongIdentityRows();
      final byPath = <String, int>{};
      // One basename index instead of scanning every local row per imported
      // song: identity resolution stays O(n + m) on large libraries.
      final byBasename = <String, List<(int duration, int id)>>{};
      for (final row in localIdentityRows) {
        final id = (row['id'] as num?)?.toInt();
        final path = row['filePath'] as String?;
        if (id == null || path == null || path.isEmpty) continue;
        byPath[normalizeBackupPath(path)] = id;
        final base = backupBasename(path);
        if (base.isEmpty || base == '/') continue;
        final duration = (row['durationMs'] as num?)?.toInt() ?? 0;
        byBasename
            .putIfAbsent(base, () => <(int duration, int id)>[])
            .add((duration, id));
      }

      final rawAliases = decoded['identityAliases'];
      final aliasMap = rawAliases is Map
          ? Map<String, dynamic>.from(rawAliases)
          : <String, dynamic>{};
      // A backup exported before a rename has no alias metadata. The local
      // alias table still knows the old path, so merge old -> current here.
      final localAliases = await DBHelper.instance.getPathAliases();
      for (final entry in localAliases.entries) {
        final current = byPath.entries
            .firstWhere((e) => e.value == entry.key,
                orElse: () => const MapEntry('', -1));
        if (current.value < 0) continue;
        for (final oldPath in entry.value) {
          aliasMap[oldPath] = current.key;
        }
      }

      int? resolveIdentity(Map<String, dynamic> raw) {
        final path = (raw['identityKey'] as String?) ??
            (raw['filePath'] as String?) ??
            '';
        final key = normalizeBackupPath(path);
        var direct = byPath[key];
        if (direct == null) {
          final canonical = aliasMap[key];
          if (canonical is String) direct = byPath[normalizeBackupPath(canonical)];
        }
        if (direct == null) {
          for (final alias in (raw['aliases'] as List? ?? const [])) {
            if (alias is! String) continue;
            final found = byPath[normalizeBackupPath(alias)];
            if (found != null) {
              direct = found;
              break;
            }
          }
        }
        if (direct != null) return direct;
        final storedBasename = (raw['basename'] as String?)?.trim() ?? '';
        final basename = backupBasename(
            storedBasename.isNotEmpty ? storedBasename : path);
        if (basename.isEmpty || basename == '/') return null;
        final duration = (raw['durationMs'] as num?)?.toInt() ?? 0;
        final candidates = <int>[];
        for (final (localDuration, localId)
            in byBasename[basename] ?? const <(int duration, int id)>[]) {
          if ((localDuration - duration).abs() <= kDurationToleranceMs) {
            candidates.add(localId);
          }
        }
        return candidates.length == 1 ? candidates.first : null;
      }

      final idMap = <int, int>{};
      for (final item in songsRaw) {
        if (item is! Map) continue;
        final raw = Map<String, dynamic>.from(item);
        final localId = resolveIdentity(raw);
        final legacyId = (raw['legacySongId'] as num?)?.toInt();
        if (localId == null) continue;
        if (legacyId != null) idMap[legacyId] = localId;
        resolvedV3Songs.add((localId, raw));
      }

      int? remap(dynamic value) {
        final id = (value as num?)?.toInt();
        return id == null ? null : idMap[id];
      }

      List<int> remapAll(Iterable<dynamic> values) {
        final out = <int>[];
        for (final value in values) {
          final mapped = remap(value);
          if (mapped != null) out.add(mapped);
        }
        return out;
      }

      for (final item in (playlistsRaw as List? ?? [])) {
        if (item is! Map) continue;
        final ids = item['songIds'];
        if (ids is List) {
          item['songIds'] = remapAll(ids);
        }
      }
      if (favoritesRaw is List) {
        favoritesRaw = remapAll(favoritesRaw);
      }
      for (final item in (entriesRaw as List? ?? [])) {
        if (item is! Map) continue;
        final mapped = remap(item['songId']);
        if (mapped != null) item['songId'] = mapped;
      }
      for (final item in (songsPlaybackRaw as List? ?? [])) {
        if (item is! Map) continue;
        final mapped = remap(item['songId']);
        if (mapped != null) item['songId'] = mapped;
      }
      for (final item in (foldersPlaybackRaw as List? ?? [])) {
        if (item is! Map) continue;
        final key = item['folderKey'] as String?;
        if (key != null && key.isNotEmpty) item['folderPath'] = key;
      }
    }

    int playlistsCreated = 0;
    // A playlist that already exists locally is a valid additive no-op, not
    // a failed restore. Count it so the summary does not cry wolf.
    int playlistsAlreadyPresent = 0;
    int membersAdded = 0;
    int favoritesRestored = 0;
    var favoritesAlreadyPresent = 0;
    int entriesRestored = 0;
    int entriesSkipped = 0;
    int membersSkipped = 0;
    int favoritesSkipped = 0;
    int songsMatched = 0;
    int songsUnmatched = 0;
    int metadataRestored = 0;
    int lyricsRestored = 0;
    int syncedLyricsRestored = 0;
    int lyricOffsetsRestored = 0;
    int bookmarksRestored = 0;
    int bookmarksSkipped = 0;

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
          final backupRule = (item['rule'] as String?)?.trim();
          final isNew = !idByName.containsKey(name);
          int playlistId;
          if (!isNew) {
            playlistId = idByName[name]!;
            playlistsAlreadyPresent++;
            // A backup restore is explicit: its rule wins over a stale local
            // one, and members are rebuilt from it at the end of the import.
            if (backupRule != null && backupRule.isNotEmpty) {
              await dbHelper.setPlaylistRule(playlistId, backupRule);
            }
          } else if (createdAt != null) {
            // Preserve the original ordering: insert with the export's
            // timestamp instead of "now".
            playlistId = await dbHelper.createPlaylistWithDate(name, createdAt,
                rule: backupRule?.isNotEmpty == true ? backupRule : null);
            idByName[name] = playlistId;
            playlistsCreated++;
          } else {
            playlistId = await dbHelper.createPlaylist(name,
                rule: backupRule?.isNotEmpty == true ? backupRule : null);
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
        final favoriteRows = await database.query('songs',
            columns: ['id'], where: 'isFavorite = 1');
        final alreadyFavorite =
            favoriteRows.map((r) => r['id'] as int).toSet();
        for (final songId in existingIds) {
          if (alreadyFavorite.contains(songId)) {
            favoritesAlreadyPresent++;
            continue;
          }
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
          final parsedTs = DateTime.tryParse(tsRaw);
          if (parsedTs == null) continue;
          // Normalize before storing and before dedup. SQLite's date
          // functions shift offset-bearing strings to UTC, which put the
          // entry in the wrong hour bucket and made the dedup triple
          // unstable across re-imports of the same backup.
          final ts = parsedTs.toLocal().toIso8601String();
          // Clamp to a sane single-session range (0 to 24h in ms) so
          // corrupt or negative values cannot skew stats.
          listenedMs = listenedMs.clamp(0, 86400000);
          final triple = '$songId|$ts|$listenedMs';
          if (!seenTriples.add(triple)) continue;
          parsedEntries.add({
            'songId': songId,
            'timestamp': ts,
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
        playlistsAlreadyPresent == 0 &&
        membersAdded == 0 &&
        favoritesRestored == 0 &&
        favoritesAlreadyPresent == 0 &&
        entriesRestored == 0 &&
        membersSkipped == 0 &&
        favoritesSkipped == 0 &&
        entriesSkipped == 0 &&
        resolvedV3Songs.isEmpty &&
        songsMatched == 0 &&
        metadataRestored == 0 &&
        syncedLyricsRestored == 0 &&
        bookmarksRestored == 0) {
      // Still a valid file shape, but nothing could be restored either.
      // Throw so the UI can tell empty/incompatible apart from success.
      final hasAnyData = ((playlistsRaw as List? ?? []).isNotEmpty) ||
          ((favoritesRaw as List? ?? []).isNotEmpty) ||
          ((entriesRaw as List? ?? []).isNotEmpty) ||
          ((decoded['songs'] as List? ?? []).isNotEmpty);
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
      final candidates = <int>[];
      final settingsBySong = <int, Map<String, dynamic>>{};
      for (final raw in (songsPlaybackRaw as List? ?? [])) {
        if (raw is! Map) continue;
        final id = (raw['songId'] as num?)?.toInt();
        if (id == null || existingSongs.containsKey(id)) continue;
        candidates.add(id);
        settingsBySong[id] = Map<String, dynamic>.from(raw);
      }
      // MediaStore ids are not stable across devices. Validate each id
      // against the local songs table before applying a gain to it.
      final database = await DBHelper.instance.db;
      final presentIds = <int>{};
      const chunk = 400;
      for (var off = 0; off < candidates.length; off += chunk) {
        final end = off + chunk > candidates.length ? candidates.length : off + chunk;
        final slice = candidates.sublist(off, end);
        final placeholders = List.filled(slice.length, '?').join(',');
        final rows = await database.rawQuery(
          'SELECT id FROM songs WHERE id IN ($placeholders)', slice);
        presentIds.addAll(rows.map((r) => r['id']).whereType<int>());
      }
      for (final id in presentIds) {
        final raw = settingsBySong[id]!;
        await DBHelper.instance.setSongPlaybackSettings(
          id,
          gainDb: (raw['gainDb'] as num?)?.toDouble() ?? 0,
          skipStartMs: (raw['skipStartMs'] as num?)?.toInt() ?? 0,
          skipEndMs: (raw['skipEndMs'] as num?)?.toInt() ?? 0,
        );
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

    // v3 song payload: manual tags, plain lyrics, synced LRC, timing offset
    // and bookmarks. Conflict policy is additive and local wins: a customized
    // local value is never overwritten by a restore.
    if (versionNumber >= 3) {
      for (final (localId, raw) in resolvedV3Songs) {
        try {
          final localRows = await DBHelper.instance.querySongById(localId);
          if (localRows == null) {
            songsUnmatched++;
            continue;
          }
          songsMatched++;
          bool isEmptyText(String? value) {
            if (value == null || value.trim().isEmpty) return true;
            return const {
              'Unknown Title',
              'Unknown Artist',
              'Unknown Album',
              'Unknown',
              'Tidak diketahui',
            }.contains(value.trim());
          }

          final title = raw['title'] as String?;
          final artist = raw['artist'] as String?;
          final album = raw['album'] as String?;
          final genre = raw['genre'] as String?;
          final region = raw['region'] as String?;
          String? localLyrics = localRows['lyrics'] as String?;
          if (localLyrics != null && localLyrics.startsWith('gz:')) {
            localLyrics = decodeLyricsFromDb(localLyrics);
          }
          String? lyrics = raw['lyrics'] as String?;
          // Stored lyrics from an older export may still be gzipped.
          if (lyrics != null && lyrics.startsWith('gz:')) {
            lyrics = decodeLyricsFromDb(lyrics);
          }
          final lrc = raw['syncedLyrics'] as String?;
          final offset = (raw['lyricOffsetMs'] as num?)?.toInt() ?? 0;

          final newTitle = isEmptyText(localRows['title'] as String?) &&
                  !isEmptyText(title)
              ? title
              : null;
          final newArtist = isEmptyText(localRows['artist'] as String?) &&
                  !isEmptyText(artist)
              ? artist
              : null;
          final newAlbum = isEmptyText(localRows['album'] as String?) &&
                  !isEmptyText(album)
              ? album
              : null;
          final newGenre = isEmptyText(localRows['genre'] as String?) &&
                  !isEmptyText(genre)
              ? genre
              : null;
          final newRegion = isEmptyText(localRows['region'] as String?) &&
                  !isEmptyText(region)
              ? region
              : null;
          final newLyrics =
              isEmptyText(localLyrics) && !isEmptyText(lyrics) ? lyrics : null;
          await DBHelper.instance.applyBackupSongMetadata(
            localId,
            title: newTitle,
            artist: newArtist,
            album: newAlbum,
            genre: newGenre,
            region: newRegion,
            lyrics: newLyrics,
            // A restored tag set is already enriched; do not let a later
            // "scan missing metadata" fetch overwrites it.
            metadataScanned: raw['metadataScanned'] == true &&
                    (newTitle != null ||
                        newArtist != null ||
                        newAlbum != null ||
                        newGenre != null ||
                        newRegion != null ||
                        newLyrics != null)
                ? true
                : null,
          );
          if (newTitle != null ||
              newArtist != null ||
              newAlbum != null ||
              newGenre != null ||
              newRegion != null) {
            metadataRestored++;
          }
          if (newLyrics != null) lyricsRestored++;

          final hasLocalLrc =
              await DBHelper.instance.getSyncedLyrics(localId) != null;
          if (!hasLocalLrc && lrc != null && lrc.isNotEmpty) {
            await DBHelper.instance.setSyncedLyrics(localId, lrc,
                offsetMs: offset);
            syncedLyricsRestored++;
            if (offset != 0) lyricOffsetsRestored++;
          }

          if (raw['isFavorite'] == true) {
            await DBHelper.instance.setFavorite(localId, true);
          }

          for (final item in (raw['bookmarks'] as List? ?? [])) {
            if (item is! Map) continue;
            final position = (item['positionMs'] as num?)?.toInt();
            if (position == null || position < 0) continue;
            final label = (item['label'] as String?) ?? '';
            final createdAt = (item['createdAt'] as String?) ??
                DateTime.now().toIso8601String();
            final inserted = await DBHelper.instance.insertBookmarkWithDate(
                localId, position, label, createdAt);
            if (inserted) {
              bookmarksRestored++;
            } else {
              bookmarksSkipped++;
            }
          }
        } catch (_) {
          // One bad song row must not abort the rest of the restore.
        }
      }
      final unresolved = resolvedV3Songs.length - songsMatched - songsUnmatched;
      if (unresolved > 0) songsUnmatched += unresolved;
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
    await SmartPlaylistService.instance.rebuildAll();
    await DBHelper.invalidateDashboardCache();

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
      songsMatched: songsMatched,
      songsUnmatched: songsUnmatched,
      metadataRestored: metadataRestored,
      lyricsRestored: lyricsRestored,
      syncedLyricsRestored: syncedLyricsRestored,
      lyricOffsetsRestored: lyricOffsetsRestored,
      bookmarksRestored: bookmarksRestored,
      bookmarksSkipped: bookmarksSkipped,
    );
  }

  // Total bytes and file count of album art files referenced by songs.
  static Future<ArtCacheUsage> artCacheUsage() async {
    int bytes = 0;
    int files = 0;
    try {
      final paths = await DBHelper.instance.getAlbumArtPaths();
      for (final path in paths) {
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
      final paths = await DBHelper.instance.getAlbumArtPaths();
      for (final path in paths) {
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
        // Clear the remote reference too. Otherwise the next scroll simply
        // downloads the same cover again and the cache is immediately full.
        await database.update(
          'songs',
          {'albumArtPath': null, 'albumArtUrl': null},
          where: "albumArtPath IS NOT NULL OR (albumArtUrl IS NOT NULL AND albumArtUrl != '')",
        );
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
