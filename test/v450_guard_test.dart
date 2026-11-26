import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.5 large feature and native polish release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('schema 14 carries timing offsets and bookmarks with cleanup', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('version: 17'), isTrue);
    expect(db.contains('offsetMs INTEGER DEFAULT 0'), isTrue);
    expect(db.contains('CREATE TABLE song_bookmarks'), isTrue);
    expect(db.contains('idx_bookmarks_song'), isTrue);
    expect(db.contains('getSyncedLyricOffset'), isTrue);
    expect(db.contains('setSyncedLyricOffset'), isTrue);
    expect(db.contains('maxBookmarksPerSong = 20'), isTrue);
    final deletes = db.split('deleteSong(int id)')[1].split('updateSongMetadata')[0];
    expect(deletes.contains("delete('song_bookmarks'"), isTrue);
    final ghosts =
        db.split('deleteSongsMissingFromDevice(')[1].split('// ---------- Playback settings')[0];
    expect(ghosts.contains("delete('song_bookmarks'"), isTrue);
  });

  test('lyric timing survives restarts and song changes', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('_lrcOffsetSaveTimer'), isTrue);
    expect(player.contains('getSyncedLyricOffset(song.id)'), isTrue);
    expect(player.contains('setSyncedLyricOffset(songId, value)'), isTrue);
    expect(player.contains('lyricsRevision.addListener'), isTrue);
    final editor = read('lib/screens/edit_lyrics_screen.dart');
    expect(editor.contains('lyricsRevision.value++'), isTrue);
    final metadata = read('lib/services/metadata_service.dart');
    expect(metadata.contains('applySyncedLyrics'), isTrue);
  });

  test('local LRC import and export stay offline', () {
    final service = read('lib/services/lrc_import_service.dart');
    expect(service.contains('FilePicker.pickFiles'), isTrue);
    expect(service.contains("allowedExtensions: const ['lrc']"), isTrue);
    expect(service.contains('maxBytes = 100 * 1024'), isTrue);
    expect(service.contains('SharePlus.instance'), isTrue);
    expect(service.contains('parseLrc(text)'), isTrue);
    final screen = read('lib/screens/edit_lyrics_screen.dart');
    expect(screen.contains('_importLrc'), isTrue);
    expect(screen.contains('_shareLrc'), isTrue);
  });

  test('bookmarks are reachable from the player', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('_openBookmarks(song)'), isTrue);
    expect(player.contains('Icons.bookmark_border'), isTrue);
    expect(player.contains('addBookmark('), isTrue);
    expect(player.contains('getBookmarks(bookmarkSongId)'), isTrue);
    expect(player.contains('SingleChildScrollView('), isTrue);
    final queue = read('lib/screens/queue_screen.dart');
    expect(queue.contains('height: scaledRowHeight(context, _itemHeight)'), isTrue);
  });

  test('dashboard has albums ranked by listening time', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('getTopAlbums({int limit = 5})'), isTrue);
    final dashboard = read('lib/screens/dashboard_screen.dart');
    expect(dashboard.contains('getTopAlbums(limit: 5)'), isTrue);
    expect(dashboard.contains('l.dashboardTopAlbums'), isTrue);
  });

  test('transport and EQ adapt to small screens and large text', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('Wrap('), isTrue);
    expect(player.contains('BoxConstraints.tightFor(width: 44, height: 44)'), isTrue);
    final eq = read('lib/widgets/eq_controls.dart');
    expect(eq.contains('MediaQuery.textScalerOf(context).scale(1.0)'), isTrue);
    final layout = read('lib/utils/row_layout.dart');
    expect(layout.contains('double scaledRowHeight('), isTrue);
    final library = read('lib/screens/library_screen.dart');
    expect(library.contains('maxScaleFactor: 1.5'), isFalse);
  });

  test('accessibility animations and notification retry are respected', () {
    final marquee = read('lib/widgets/marquee_text.dart');
    expect(marquee.contains('reduceMotion(context)'), isTrue);
    final indicator = read('lib/widgets/playing_indicator.dart');
    expect(indicator.contains('_reducedMotion'), isTrue);
    final permissions = read('lib/services/permission_service.dart');
    expect(permissions.contains('isPermanentlyDenied'), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('settingsNotificationsSubtitle'), isTrue);
  });
}
