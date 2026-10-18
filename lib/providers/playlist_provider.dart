import 'package:flutter/foundation.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:swara/providers/language_provider.dart';
import '../models/song.dart';
import '../services/db_helper.dart';

class PlaylistProvider extends ChangeNotifier {
  List<Map<String, dynamic>> playlists = [];

  Future<void> load() async {
    playlists = await DBHelper.instance.getPlaylists();
    notifyListeners();
  }

  Future<void> create(String name) async {
    await DBHelper.instance.createPlaylist(name);
    await load();
  }

  Future<void> delete(int id) async {
    await DBHelper.instance.deletePlaylist(id);
    await load();
  }

  Future<void> addSong(int playlistId, int songId) async {
    try {
      // The DB uses ConflictAlgorithm.ignore so duplicates do not throw
      // a SQLite error - check explicitly so the UI gets a clear message.
      final current = await DBHelper.instance.getSongsInPlaylist(playlistId);
      if (current.any((s) => s.id == songId)) {
        throw Exception(lookupAppLocalizations(LanguageProvider.instance.locale).coreSongAlreadyInPlaylist);
      }
      await DBHelper.instance.addSongToPlaylist(playlistId, songId);
      notifyListeners();
    } catch (e) {
      if (e.toString().contains('UNIQUE')) {
        throw Exception(lookupAppLocalizations(LanguageProvider.instance.locale).coreSongAlreadyInPlaylist);
      }
      rethrow;
    }
  }

  /// Add many songs with a single write and a single notification.
  ///
  /// Returns the number of songs that were really added, which is lower than
  /// [songIds].length when some of them were already in the playlist.
  Future<int> addSongs(int playlistId, List<int> songIds) async {
    try {
      final added = await DBHelper.instance.addSongsToPlaylist(
        playlistId,
        songIds,
      );
      if (added > 0) notifyListeners();
      return added;
    } catch (e) {
      if (e.toString().contains('UNIQUE')) {
        throw Exception(lookupAppLocalizations(
            LanguageProvider.instance.locale).coreSongAlreadyInPlaylist);
      }
      rethrow;
    }
  }

  Future<void> removeSong(int playlistId, int songId) async {
    try {
      await DBHelper.instance.removeSongFromPlaylist(playlistId, songId);
      notifyListeners();
    } catch (e) {
      throw Exception('${lookupAppLocalizations(LanguageProvider.instance.locale).coreRemoveFromPlaylistFailed}: $e');
    }
  }

  Future<List<Song>> songsIn(int playlistId) =>
      DBHelper.instance.getSongsInPlaylist(playlistId);

  Future<void> reorder(int playlistId, List<int> songIdsInOrder) async {
    try {
      await DBHelper.instance.reorderPlaylistSongs(playlistId, songIdsInOrder);
      notifyListeners();
    } catch (e) {
      throw Exception('${lookupAppLocalizations(LanguageProvider.instance.locale).coreSavePlaylistOrderFailed}: $e');
    }
  }
}
