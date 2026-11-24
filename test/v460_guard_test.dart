import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.6 stable-identity backup and native polish release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('backup v3 uses stable file identity and restores user data', () {
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('kBackupFormatVersion = 3'), isTrue);
    expect(backup.contains('normalizeBackupPath('), isTrue);
    expect(backup.contains('kDurationToleranceMs = 1000'), isTrue);
    expect(backup.contains("payload['songs'] = songsJson"), isTrue);
    expect(backup.contains('syncedLyrics'), isTrue);
    expect(backup.contains('lyricOffsetMs'), isTrue);
    expect(backup.contains('insertBookmarkWithDate('), isTrue);
    expect(backup.contains('applyBackupSongMetadata('), isTrue);
    expect(backup.contains('favoritesRaw = remapAll(favoritesRaw)'), isTrue);
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('getSongIdentityRows()'), isTrue);
    expect(db.contains('querySongById(int id)'), isTrue);
    expect(db.contains('idx_listening_julianday'), isTrue);
  });

  test('backup save uses the system file picker', () {
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('FilePicker.saveFile('), isTrue);
    expect(backup.contains("mimeType: 'application/json'"), isTrue);
    expect(backup.contains('await getDownloadsDirectory()'), isFalse);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('dataBackupSavedSaf(savedName)'), isTrue);
    expect(settings.contains('user cancelled the picker'), isTrue);
  });

  test('lyric timing survives quick exit and edits', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('_flushPendingLrcOffset()'), isTrue);
    expect(player.contains('_lrcLoadGeneration'), isTrue);
    expect(player.contains('generation != _lrcLoadGeneration'), isTrue);
    final service = read('lib/services/lrc_import_service.dart');
    expect(service.contains('getSyncedLyricOffset(song.id)'), isTrue);
    expect(service.contains('offsetMs: offset'), isTrue);
  });

  test('bookmarks stay bound to one song and do not flash empty', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('bookmarkSongId'), isTrue);
    expect(player.contains('getBookmarks(bookmarkSongId)'), isTrue);
    expect(player.contains('lastRows = data'), isTrue);
  });

  test('reduced motion covers the visible animated widgets', () {
    final motion = read('lib/utils/motion.dart');
    expect(motion.contains('motionDuration('), isTrue);
    for (final path in [
      'lib/screens/player_screen.dart',
      'lib/screens/search_screen.dart',
      'lib/screens/library_screen.dart',
      'lib/widgets/eq_controls.dart',
      'lib/widgets/mini_player.dart',
    ]) {
      expect(read(path).contains('motionDuration(context,'), isTrue,
          reason: '$path must honour reduce motion');
    }
  });

  test('dense controls adapt to 320dp and 2x text', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('Wrap('), isTrue);
    expect(player.contains('readoutWidth'), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('maxLines: 2'), isTrue);
  });

  test('l10n keys for backup v3 exist', () {
    for (final name in ['app_en.arb', 'app_id.arb']) {
      final arb = read('lib/l10n/$name');
      expect(arb.contains('dataImportDoneV3'), isTrue);
      expect(arb.contains('dataImportSkippedV3'), isTrue);
      expect(arb.contains('dataBackupSavedSaf'), isTrue);
    }
  });
}
