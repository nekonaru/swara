import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v2.9.7 performance work. Each check pins the structural
// change that made the app lighter, because the slow version looks
// reasonable and is easy to reintroduce during a refactor.

void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('single row actions patch in memory instead of reloading', () {
    final provider = read('lib/providers/library_provider.dart');
    expect(provider.contains('bool _patchSongInMemory('), isTrue,
        reason: 'metadata edits must patch one row, not reload the table');
    expect(provider.contains('bool _setFavoriteInMemory('), isTrue,
        reason: 'a favorite toggle must not reload the whole library');
    expect(provider.contains('Song? songById(int id)'), isTrue,
        reason: 'per rebuild lookups must use an index, not a scan');
    // The lowercased sort key used to be computed for both sides on every
    // comparison, which allocated hundreds of thousands of strings per load.
    expect(provider.contains('a.artist.toLowerCase().compareTo'), isFalse,
        reason: 'sort keys must be precomputed once per song');
    expect(provider.contains('void _sortByTitle('), isTrue);
    expect(provider.contains('void _sortByKey('), isTrue);
  });

  test('search matching runs in an isolate, not on the UI thread', () {
    final search = read('lib/screens/search_screen.dart');
    expect(search.contains('compute(filterSongsIsolate'), isTrue,
        reason: 'the fuzzy pass must stay off the UI thread');
    // Direct in method calls would put the normalization regexes and the
    // edit distance pass back on the frame that the user is typing on.
    expect(search.contains('fuzzyMatch('), isFalse,
        reason: 'matching belongs in utils/search_filter.dart');
    expect(search.contains('suggestFor('), isFalse);

    final util = read('lib/utils/search_filter.dart');
    expect(util.contains('Map<String, dynamic> filterSongsIsolate('), isTrue);
  });

  test('the player screen resolves the playing song by index', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('lib.songs.where((s) => s.id == song.id)'), isFalse,
        reason: 'scanning the library on every rebuild is the jank source');
    expect(player.contains('lib.songById(song.id)'), isTrue);
  });
}
