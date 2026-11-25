import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:swara/l10n/gen/app_localizations.dart';

import '../models/song.dart';
import '../providers/language_provider.dart';
import '../utils/format.dart';
import 'db_helper.dart';
import 'player_service.dart';

/// Offline Android Auto browse tree. All identities live in the media id
/// string because audio_service drops the extras map on Android.
class SwaraBrowseCatalog {
  SwaraBrowseCatalog._();

  static const String root = 'root';
  static const String recent = 'recent';
  static const String catPlaylists = 'cat_playlists';
  static const String catFolders = 'cat_folders';
  static const String catSongs = 'cat_songs';
  static const String catQueue = 'cat_queue';
  static const int maxChildren = 50;

  static String _category(String id) => 'cat_$id';

  static MediaItem _leaf(Song song, {String? id}) => MediaItem(
        id: id ?? 'queue_-1_${song.filePath}',
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: Duration(milliseconds: song.durationMs),
        artUri: _artUri(song.albumArtPath),
      );

  static Uri? _artUri(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    try {
      if (!File(path).existsSync()) return null;
      return Uri.file(path);
    } catch (_) {
      return null;
    }
  }

  static Future<List<MediaItem>> childrenFor(String parentId) async {
    final l = lookupAppLocalizations(LanguageProvider.instance.locale);
    if (parentId == root) {
      return [
        MediaItem(id: catPlaylists, title: l.autoBrowsePlaylists,
            artist: '', album: '', playable: false),
        MediaItem(id: catFolders, title: l.homeTabFolders,
            artist: '', album: '', playable: false),
        MediaItem(id: catSongs, title: l.homeTabSongs,
            artist: '', album: '', playable: false),
        MediaItem(id: catQueue, title: l.queueTitle,
            artist: '', album: '', playable: false),
      ];
    }
    if (parentId == recent) {
      final rows = await DBHelper.instance.getRecentlyPlayed(limit: 1);
      return [for (final song in rows) _leaf(song)];
    }
    if (parentId == catPlaylists) {
      final rows = await DBHelper.instance.getPlaylists();
      return [
        for (final row in rows)
          if ((row['name'] as String?)?.isNotEmpty == true)
            MediaItem(
              id: _category('playlist_${row['id']}'),
              title: row['name'] as String,
              artist: '',
              album: '',
              playable: false,
            ),
      ];
    }
    if (parentId.startsWith('cat_playlist_')) {
      final id = int.tryParse(parentId.substring('cat_playlist_'.length));
      if (id == null) return const <MediaItem>[];
      final songs = await DBHelper.instance.getSongsInPlaylist(id);
      return [
        for (final song in songs.take(maxChildren)) _leaf(song),
      ];
    }
    if (parentId == catFolders) {
      final excluded = await DBHelper.instance.getExcludedFolders();
      final folders = <String>{};
      for (final song in await DBHelper.instance.getSongSummaries()) {
        final folder = folderOf(song.filePath);
        if (folder.isEmpty || excluded.contains(folder)) continue;
        folders.add(folder);
      }
      return [
        for (final folder in folders.take(maxChildren))
          MediaItem(
            id: _category('folder_${Uri.encodeQueryComponent(folder)}'),
            title: folder.split('/').last,
            artist: '',
            album: '',
            playable: false,
          ),
      ];
    }
    if (parentId.startsWith('cat_folder_')) {
      String folder;
      try {
        folder = Uri.decodeQueryComponent(
            parentId.substring('cat_folder_'.length));
      } catch (_) {
        return const <MediaItem>[];
      }
      return [
        for (final song in (await DBHelper.instance.getSongSummaries())
            .where((s) => folderOf(s.filePath) == folder)
            .take(maxChildren))
          _leaf(song),
      ];
    }
    if (parentId == catSongs) {
      final excluded = await DBHelper.instance.getExcludedFolders();
      return [
        for (final song in (await DBHelper.instance.getSongSummaries())
            .where((s) => !excluded.contains(folderOf(s.filePath)))
            .take(maxChildren))
          _leaf(song),
      ];
    }
    if (parentId == catQueue) {
      final service = PlayerService.instance;
      final queue = service.queue;
      final out = <MediaItem>[];
      for (var i = 0; i < queue.length && i < maxChildren; i++) {
        final song = queue[i];
        final slot = service.queueSlotIdAt(i);
        out.add(_leaf(song,
            id: 'queue_${slot ?? -1}_${song.filePath}'));
      }
      return out;
    }
    return const <MediaItem>[];
  }

  static Future<List<MediaItem>> search(String query) async {
    if (query.trim().isEmpty) return const <MediaItem>[];
    final excluded = await DBHelper.instance.getExcludedFolders();
    final rows = await DBHelper.instance.querySongsPage(
      query: query,
      limit: maxChildren,
      offset: 0,
      excludedFolders: excluded,
      orderBy: 'title ASC',
    );
    return [for (final song in rows) _leaf(song)];
  }
}
