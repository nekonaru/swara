import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:swara/providers/language_provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'db_helper.dart';
import '../utils/format.dart';

// ── Isolate data shapes ───────────────────────────────────────────────
// Plain serialisable stand-ins for SongModel so track data can cross the
// isolate boundary. Only the fields needed for merge/upsert are carried.

class _RawTrack {
  final int id;
  final String data;
  final String title;
  final String artist;
  final String album;
  final int? duration;
  _RawTrack({
    required this.id,
    required this.data,
    required this.title,
    required this.artist,
    required this.album,
    this.duration,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'data': data,
    'title': title,
    'artist': artist,
    'album': album,
    'duration': duration,
  };
  factory _RawTrack.fromJson(Map<String, dynamic> j) => _RawTrack(
    id: j['id'] as int,
    data: j['data'] as String,
    title: j['title'] as String,
    artist: j['artist'] as String,
    album: j['album'] as String,
    duration: j['duration'] as int?,
  );
}

class _ScanResult {
  final List<Map<String, dynamic>> pendingMaps;
  final List<Map<String, dynamic>> pendingUpdates;
  final List<int> updateIds;
  final List<Song> result;
  final Set<int> allDeviceIds;
  _ScanResult({
    required this.pendingMaps,
    required this.pendingUpdates,
    required this.updateIds,
    required this.result,
    required this.allDeviceIds,
  });
}

/// Isolate entry: process raw tracks off the main thread. Helpers that the
/// main thread used to call (folderOf, title fallback) are duplicated here
/// so the isolate never imports Flutter or sqflite code.
_ScanResult _processTracksIsolate(Map<String, dynamic> input) {
  final tracksJson = (input['tracks'] as List).cast<Map<String, dynamic>>();
  final excluded = (input['excluded'] as List).cast<String>();
  // Copied across the isolate boundary with its original generic type, so
  // it may be a Map<int, ...>. Read it as an untyped map and keep int keys.
  final existingById = Map<Object?, Object?>.from(
      input['existingById'] as Map);

  // Mirrors utils/format.dart folderOf so the exclusion check matches what
  // the main-thread version did before the work moved into the isolate.
  String folderOfPath(String filePath) {
    final normalized = filePath.replaceAll(r'\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? '' : normalized.substring(0, idx);
  }

  String _titleFromFilename(String path) {
    final normalized = path.replaceAll(r'\\', '/');
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    return name
        .replaceAll(RegExp(r'\.(mp3|flac|wav|m4a|ogg|opus|aac|wma)$',
            caseSensitive: false), '')
        .trim();
  }

  final pendingMaps = <Map<String, dynamic>>[];
  final pendingUpdates = <Map<String, dynamic>>[];
  final updateIds = <int>[];
  final result = <Song>[];
  final allDeviceIds = <int>{};

  for (final tj in tracksJson) {
    final track = _RawTrack.fromJson(tj);
    allDeviceIds.add(track.id);
    final folder = folderOfPath(track.data);
    if (excluded.contains(folder)) continue;

    final title = (track.title.isNotEmpty)
        ? track.title
        : _titleFromFilename(track.data);
    final artist = (track.artist.isNotEmpty && track.artist != '<unknown>')
        ? track.artist
        : 'Unknown Artist';
    final album = track.album.isNotEmpty ? track.album : 'Unknown Album';
    final song = Song(
      id: track.id,
      filePath: track.data,
      title: title,
      artist: artist,
      album: album,
      durationMs: track.duration ?? 0,
    );
    final existing = existingById[song.id];
    if (existing != null) {
      pendingUpdates.add({
        'filePath': song.filePath,
        'durationMs': song.durationMs,
      });
      updateIds.add(song.id);
      result.add(song);
      continue;
    }
    final map = song.toMap();
    map['addedAt'] = DateTime.now().toIso8601String();
    pendingMaps.add(map);
    result.add(song);
  }
  return _ScanResult(
    pendingMaps: pendingMaps,
    pendingUpdates: pendingUpdates,
    updateIds: updateIds,
    result: result,
    allDeviceIds: allDeviceIds,
  );
}

class LibraryScanner {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<bool> requestPermission() async {
    final status = await Permission.audio.request();
    if (status.isGranted) return true;
    // fallback for Android < 13
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  // Returns true when the audio permission is permanently denied,
  // so the caller can direct the user to the app settings.
  Future<bool> isPermanentlyDenied() async {
    return Permission.audio.isPermanentlyDenied;
  }

  /// Scan every music file on the device and store new ones in the DB.
  /// Metadata fetching is never automatic; call bulkScanMetadata or
  /// rescanSingleMetadata manually when the user asks for it.
  Future<List<Song>> scanAndSync() async {
    final granted = await requestPermission();
    if (!granted) {
      throw Exception(lookupAppLocalizations(LanguageProvider.instance.locale).corePermissionDenied);
    }

    final excluded = await DBHelper.instance.getExcludedFolders();
    final database = await DBHelper.instance.db;
    // Single SELECT for every stored row state needed below, keyed by id.
    // This replaces one SELECT per song inside upsertSong, so a library of
    // N songs costs 1 read plus 1 batched write instead of N round trips.
    final existingRows = await database.query('songs', columns: ['id']);
    // Snapshot of the ids present BEFORE querySongs() runs. The ghost cleanup
    // must compare against this snapshot, never a live read of the songs
    // table: a second scan running in parallel would insert new rows that the
    // first scan would then mistake for deleted files.
    final dbIdsAtScanStart = <int>{
      for (final row in existingRows)
        if (row['id'] is int) row['id'] as int,
    };
    final existingById = <int, Map<String, Object?>>{
      for (final row in existingRows)
        if (row['id'] is int) row['id'] as int: row,
    };
    final tracks = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
    );

    // IDs of ALL songs that truly still exist on the device (including ones in
    // hidden folders) - used to clean up "ghost" songs without also deleting
    // songs that are merely hidden (not really gone).
    final allDeviceIdsOnMain = tracks.map((t) => t.id).toSet();

    // Safety guard: never delete anything when querySongs() looks like it
    // returned a suspicious result - the MediaStore may not have finished
    // indexing, storage permission may have just been granted (race condition),
    // or the plugin may have failed temporarily. Without this guard, the whole
    // library could be wiped from the DB even though the files are still on
    // the phone.
    //
    // Conditions treated as unsafe:
    //   1. The device returns no songs at all (the most dangerous case)
    //   2. The song count drops by more than 50% versus what is already in the
    //      DB in a single scan - a normal drop is only a few songs (files the
    //      user really deleted), never half the library at once.
    final bool safeToDelete;
    if (allDeviceIdsOnMain.isEmpty) {
      safeToDelete = false;
    } else {
      final dbCount = await DBHelper.instance.getSongCount();
      if (dbCount > 0 && allDeviceIdsOnMain.length < dbCount * 0.5) {
        safeToDelete = false;
      } else {
        safeToDelete = true;
      }
    }

    // Move the heavy per-track processing off the main thread. querySongs()
    // is a platform channel call so it stays on the main thread above; the
    // folder exclusion checks, Song construction, and pending-operation
    // building happen inside an isolate.
    final tracksJson = tracks
        .map((t) => _RawTrack(
              id: t.id,
              data: t.data,
              title: t.title,
              artist: t.artist ?? '',
              album: t.album ?? '',
              duration: t.duration,
            ).toJson())
        .toList();
    final scanResult = await compute(_processTracksIsolate, <String, dynamic>{
      'tracks': tracksJson,
      'excluded': excluded,
      'existingById': existingById,
    });

    final pendingMaps = scanResult.pendingMaps;
    final pendingUpdates = scanResult.pendingUpdates;
    final updateIds = scanResult.updateIds;
    final result = scanResult.result;
    final allDeviceIds = scanResult.allDeviceIds;
    if (pendingMaps.isNotEmpty || pendingUpdates.isNotEmpty) {
      final batch = database.batch();
      for (final map in pendingMaps) {
        batch.insert('songs', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (var i = 0; i < pendingUpdates.length; i++) {
        batch.update(
          'songs',
          pendingUpdates[i],
          where: 'id = ?',
          whereArgs: [updateIds[i]],
        );
      }
      await batch.commit(noResult: true);
    }

    // Clean up "ghost" songs - rows in the DB whose original files were
    // deleted/moved from the phone outside the app.
    // Only runs when querySongs() returns a sane result (see the guard above).
    if (safeToDelete) {
      // Pass the snapshot so a parallel scan cannot have its freshly inserted
      // rows deleted as ghosts by this one.
      await DBHelper.instance.deleteSongsMissingFromDevice(
        allDeviceIds,
        knownDbIds: dbIdsAtScanStart,
      );
    }

    return result;
  }

  /// Unique list of folders where music files were found, for the "Song Folders" feature
  Future<List<String>> listMusicFolders() async {
    final all = await DBHelper.instance.getAllSongs();
    final folders = <String>{};
    for (final s in all) {
      folders.add(folderOf(s.filePath));
    }
    return folders.toList()..sort();
  }

  Future<List<Song>> getSongsInFolder(String folderPath) async {
    final all = await DBHelper.instance.getAllSongs();
    // Append a trailing '/' so '/storage/Music' never matches '/storage/Music2'
    return all.where((s) => s.filePath.startsWith('$folderPath/')).toList();
  }
}
