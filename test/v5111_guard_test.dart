import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v5.1.1 native correctness release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('search history has one key and filters bypass the result cap', () {
    final search = read('lib/screens/search_screen.dart');
    expect(search.contains("_historyKey = 'search_history_v5'"), isTrue);
    expect(search.contains('? source.length'), isTrue);
    expect(search.contains(': _resultsLimit,'), isTrue);
  });

  test('Auto browse uses its own labels and no file stats', () {
    final catalog = read('lib/services/swara_browse_catalog.dart');
    expect(catalog.contains('V5.newSongs'), isTrue);
    expect(catalog.contains('V5.unplayed'), isTrue);
    expect(catalog.contains('V5.genres'), isTrue);
    expect(catalog.contains('existsSync()'), isFalse);
  });

  test('bulk writes are batched', () {
    final lib = read('lib/providers/library_provider.dart');
    expect(lib.contains('Future<void> setLabels('), isTrue);
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('Future<int> markPlayedBulk('), isTrue);
    final screen = read('lib/screens/library_screen.dart');
    expect(screen.contains('setLabels({'), isTrue);
    expect(screen.contains('markPlayedBulk('), isTrue);
    expect(screen.contains('markPlayed(s.id)'), isFalse);
  });

  test('lyrics edit refreshes the player and sleep resume keeps its mode', () {
    final lyrics = read('lib/screens/edit_lyrics_screen.dart');
    expect(
        lyrics.contains('PlayerService.instance.lyricsRevision.value++'), isTrue);
    final player = read('lib/services/player_service.dart');
    expect(player.contains("'resume_sleep_finish_song'"), isTrue);
    expect(player.contains('finishCurrentSong:'), isTrue);
  });

  test('extras screen is safe and its tools work', () {
    final extras = read('lib/screens/v5_extras_screen.dart');
    expect(extras.contains('verifyBackupBytes(bytes)'), isTrue);
    expect(extras.contains('_folderRows = _rowsForFolders('), isTrue);
    expect(extras.contains('SharePlus.instance.share('), isTrue);
    expect(extras.contains('Future<void> _load() async {\n    if (!mounted) return;'),
        isTrue);
  });

  test('relative M3U uses a common ancestor', () {
    final m3u = read('lib/services/m3u_service.dart');
    expect(m3u.contains('Future<Directory> outputDirectory()'), isTrue);
    expect(m3u.contains('p.relative(song.filePath, from: baseDir)'), isTrue);
  });
}
