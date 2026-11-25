import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.7 feature and performance release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('lyric timing can be reset with one tap', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('Future<void> _resetLrcOffset()'), isTrue);
    expect(player.contains('playerLyricTimingReset'), isTrue);
    expect(player.contains('_writeLrcOffset(songId, 0)'), isTrue);
  });

  test('bookmarks can be renamed and stay bound to one song', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('updateBookmarkLabel('), isTrue);
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('playerBookmarkRename'), isTrue);
    expect(player.contains('playerBookmarkSongChanged'), isTrue);
    expect(player.contains('_player.currentSong?.id != bookmarkSongId'), isTrue);
  });

  test('backup export and identity resolution are batched', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('getBackupSongExtras('), isTrue);
    expect(db.contains('clearPlaylistSongs('), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('byBasename'), isTrue);
    expect(backup.contains('getBackupSongExtras('), isTrue);
    expect(backup.contains('metadataScanned: raw[\'metadataScanned\']'), isTrue);
    expect(backup.contains('resolvedV3Songs.isEmpty &&'), isTrue);
  });

  test('import summary uses one snackbar', () {
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('final summary = StringBuffer('), isTrue);
    expect(settings.contains('_showSnack(summary.toString())'), isTrue);
  });

  test('widget no longer force pushes on ordinary playback', () {
    final main = read('lib/main.dart');
    expect(main.contains('lastTickPositionMs'), isTrue);
    expect(main.contains('hasTick && (positionMs - lastTickPositionMs)'), isTrue);
    expect(main.contains('lastSeenPositionMs'), isFalse);
  });

  test('warm DB open skips existing indexes', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('sqlite_master'), isTrue);
    expect(db.contains('if (existing.contains(entry.key)) continue;'), isTrue);
  });

  test('art probing skips songs with a usable cover', () {
    final art = read('lib/widgets/song_art_image.dart');
    expect(art.contains('hasRealCover'), isTrue);
    expect(art.contains('existsSync()'), isTrue);
    expect(art.contains('!hasRealCover'), isTrue);
  });

  test('new l10n keys exist in both locales', () {
    for (final name in ['app_en.arb', 'app_id.arb']) {
      final arb = read('lib/l10n/$name');
      expect(arb.contains('playerLyricTimingReset'), isTrue);
      expect(arb.contains('playerBookmarkRename'), isTrue);
      expect(arb.contains('playerBookmarkSongChanged'), isTrue);
    }
  });
}
