import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v5 large feature release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('v17 schema carries labels and trash', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('version: 17'), isTrue);
    expect(db.contains('CREATE TABLE song_labels'), isTrue);
    expect(db.contains('CREATE TABLE trash_songs'), isTrue);
    expect(db.contains('Future<bool> moveSongToTrash('), isTrue);
    expect(db.contains('Future<bool> restoreFromTrash('), isTrue);
  });

  test('library exposes labels, trash and volume filter', () {
    final lib = read('lib/providers/library_provider.dart');
    expect(lib.contains('Map<int, String> labels'), isTrue);
    expect(lib.contains('Future<bool> moveToTrash('), isTrue);
    expect(lib.contains('Future<void> setVolumeFilter('), isTrue);
    final options = read('lib/utils/song_options.dart');
    expect(options.contains('V5.setLabel'), isTrue);
    expect(options.contains('V5.trashConfirm'), isTrue);
  });

  test('bulk actions cover label, played, export, share and trash', () {
    final screen = read('lib/screens/library_screen.dart');
    for (final needle in [
      '_bulkLabel(selected)',
      'DBHelper.instance',
      'markPlayedBulk(',
      'M3uService.buildM3uContent(selected)',
      'SharePlus.instance.share(',
      '_bulkTrash(selected)',
    ]) {
      expect(screen.contains(needle), isTrue, reason: needle);
    }
  });

  test('search has advanced filters and history', () {
    final search = read('lib/screens/search_screen.dart');
    expect(search.contains('_genreFilter'), isTrue);
    expect(search.contains('_yearFilter'), isTrue);
    expect(search.contains('_labelFilter'), isTrue);
    expect(search.contains('_buildHistoryChips()'), isTrue);
  });

  test('playback has history, resume extras and speed presets', () {
    final player = read('lib/services/player_service.dart');
    expect(player.contains('List<Song> get sessionHistory'), isTrue);
    expect(player.contains('Future<void> playSongAgain('), isTrue);
    expect(player.contains("'resume_ab_a_ms'"), isTrue);
    expect(player.contains("'resume_sleep_songs'"), isTrue);
    final screen = read('lib/screens/player_screen.dart');
    expect(screen.contains('_showSessionHistory'), isTrue);
    expect(screen.contains('const [0.75, 1.0, 1.25, 1.5, 2.0]'), isTrue);
  });

  test('lyrics get a timeline editor and filename parser', () {
    final lyrics = read('lib/screens/edit_lyrics_screen.dart');
    expect(lyrics.contains('_openTimelineEditor'), isTrue);
    final meta = read('lib/screens/edit_metadata_screen.dart');
    expect(meta.contains('FilenameTagService.parse('), isTrue);
    expect(meta.contains('_pickCustomCover'), isTrue);
  });

  test('auto browse gains new, unplayed and genre categories', () {
    final catalog = read('lib/services/swara_browse_catalog.dart');
    for (final id in [
      'catNew',
      'catUnplayed',
      'catGenres',
      'genrePrefix',
    ]) {
      expect(catalog.contains(id), isTrue, reason: id);
    }
    final smart = read('lib/services/smart_playlist_service.dart');
    expect(smart.contains("'Newly Added'"), isTrue);
    expect(smart.contains("'Most Played'"), isTrue);
  });

  test('extras screen hosts tools and is reachable', () {
    final extras = read('lib/screens/v5_extras_screen.dart');
    for (final needle in [
      'BackupService.verifyBackup',
      'folderCounts(songs)',
      'DiagnosticsService.instance.lines',
      'WidgetSettingsService.setQueueLength',
      'M3uService.buildM3uContent',
    ]) {
      expect(extras.contains(needle), isTrue, reason: needle);
    }
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('V5.moreTools'), isTrue);
  });

  test('deletion still asks first', () {
    final options = read('lib/utils/song_options.dart');
    expect(options.contains('V5.trashConfirm(song.title)'), isTrue);
    final extras = read('lib/screens/v5_extras_screen.dart');
    expect(extras.contains('Future<void> _confirm('), isTrue);
  });
}
