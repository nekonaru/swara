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

  static (int page, int pageSize) pageOf(Map<String, dynamic>? options) {
    final rawPage = options?['page'] ??
        options?['android.media.browse.extra.PAGE'];
    final rawSize = options?['pageSize'] ??
        options?['android.media.browse.extra.PAGE_SIZE'];
    final page = (rawPage is num ? rawPage.toInt() : 0).clamp(0, 1 << 20);
    final size = (rawSize is num ? rawSize.toInt() : maxChildren).clamp(1, 100);
    return (page, size);
  }

  static Future<List<MediaItem>> childrenFor(
    String parentId, [
    Map<String, dynamic>? options,
  ]) async {
    final l = lookupAppLocalizations(LanguageProvider.instance.locale);
    final (page, pageSize) = pageOf(options);
    final offset = page * pageSize;
    if (parentId == root) {
      final categories = [
        MediaItem(id: recent, title: l.autoBrowseRecent,
            artist: '', album: '', playable: false),
        MediaItem(id: catPlaylists, title: l.autoBrowsePlaylists,
            artist: '', album: '', playable: false),
        MediaItem(id: catFolders, title: l.homeTabFolders,
            artist: '', album: '', playable: false),
        MediaItem(id: catSongs, title: l.homeTabSongs,
            artist: '', album: '', playable: false),
        MediaItem(id: catQueue, title: l.queueTitle,
            artist: '', album: '', playable: false),
      ];
      // Android Auto paginates until a short page arrives. Returning all five
      // on every page would loop forever with a small page size.
      return categories.skip(offset).take(pageSize).toList();
    }
    if (parentId == recent) {
      final excluded = await DBHelper.instance.getExcludedFolders();
      final rows = await DBHelper.instance.getRecentlyPlayed(
        limit: pageSize,
        offset: offset,
        excludedFolders: excluded,
      );
      return [for (final song in rows) _leaf(song)];
    }
    if (parentId == catPlaylists) {
      final rows = await DBHelper.instance.getPlaylistsPage(
          limit: pageSize, offset: offset);
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
      final songs = await DBHelper.instance.getSongsInPlaylistPage(id,
          limit: pageSize, offset: offset);
      return [for (final song in songs) _leaf(song)];
    }
    if (parentId == catFolders) {
      final excluded = await DBHelper.instance.getExcludedFolders();
      final folders = await DBHelper.instance.getMusicFoldersPage(
        limit: pageSize,
        offset: offset,
        excludedFolders: excluded,
      );
      return [
        for (final folder in folders)
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
      final rows = (await DBHelper.instance.getSongSummaries())
          .where((s) =>
              folderOf(s.filePath) == folder ||
              isHiddenPath(s.filePath, {folder}))
          .skip(offset)
          .take(pageSize);
      return [for (final song in rows) _leaf(song)];
    }
    if (parentId == catSongs) {
      final excluded = await DBHelper.instance.getExcludedFolders();
      final rows = await DBHelper.instance.querySongsPage(
        query: '',
        limit: pageSize,
        offset: offset,
        excludedFolders: excluded,
        orderBy: 'title ASC',
      );
      return [for (final song in rows) _leaf(song)];
    }
    if (parentId == catQueue) {
      final service = PlayerService.instance;
      final out = <MediaItem>[];
      for (var i = offset;
          i < service.queueOrderLength && out.length < pageSize;
          i++) {
        final song = service.songAtOrderIndex(i);
        if (song == null) continue;
        final slot = service.queueSlotIdAt(i);
        out.add(_leaf(song,
            id: 'queue_${slot ?? -1}_${song.filePath}'));
      }
      return out;
    }
    return const <MediaItem>[];
  }

  static Future<List<MediaItem>> search(String query,
      [int limit = maxChildren]) async {
    if (query.trim().isEmpty) return const <MediaItem>[];
    final excluded = await DBHelper.instance.getExcludedFolders();
    final rows = await DBHelper.instance.querySongsPage(
      query: query,
      limit: limit,
      offset: 0,
      excludedFolders: excluded,
      orderBy: 'title ASC',
    );
    return [for (final song in rows) _leaf(song)];
  }
}
