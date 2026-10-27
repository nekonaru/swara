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

  // Guards for the v2.9.8 round: hoisted regexes, cached derived views and a
  // throttled art cache touch. Same reasoning as above, the slow version
  // looks reasonable and is easy to bring back.
  group('v2.9.8 light paths', () {
    test('fuzzy normalization compiles its regexes once, not per call', () {
      final fuzzy = read('lib/utils/fuzzy.dart');
      expect(fuzzy.contains("RegExp(r'[^\\p{L}\\p{N}]+', unicode: true)"), isTrue);
      // The two patterns must live at file scope, so no RegExp literal may
      // remain inside the normalize() body.
      final normalizeBody = fuzzy.split('String normalize(String text) {')[1];
      expect(normalizeBody.split('\n}').first.contains('RegExp('), isFalse,
          reason: 'normalize runs per row per query, regexes must be hoisted');
    });

    test('the search isolate normalizes once per row and per run', () {
      final isolate = read('lib/utils/search_filter.dart');
      expect(isolate.contains('normalize(query)'), isTrue,
          reason: 'the query must be normalized once per run');
      expect(isolate.contains('fuzzyMatchNormalized('), isTrue);
      expect(isolate.contains('fuzzyMatchLooseNormalized('), isTrue);
      // One normalize per row, none inside the matchers.
      expect(isolate.contains('fuzzyMatch(haystack'), isFalse,
          reason: 'the raw wrappers re-normalize both sides per row');
      expect(isolate.contains('fuzzyMatchLoose(haystack'), isFalse);
    });

    test('the playlist detail view is cached per source, sort and query', () {
      final playlist = read('lib/screens/playlist_detail_screen.dart');
      expect(playlist.contains('List<Song>? _displayedCache;'), isTrue,
          reason: 'the sorted view must not be rebuilt on every build');
      // Exactly one occurrence: the hoisted _leadingLetterReg. Any second one
      // means the pattern is being compiled per row or per build again.
      final matches = RegExp(r"RegExp\(r'\^\[a-zA-Z\]'\)")
          .allMatches(playlist)
          .length;
      expect(matches, 1,
          reason: 'the A-Z letter regex must be compiled once, not per row');
    });

    test('sort rank checks ASCII ranges instead of running regexes', () {
      final format = read('lib/utils/format.dart');
      expect(format.contains('_latinReg'), isFalse,
          reason: 'a regex per comparison is the old sort hot path');
      expect(format.contains('c >= 0x41 && c <= 0x5A'), isTrue);
    });

    test('the favorites list is cached per library version', () {
      final provider = read('lib/providers/library_provider.dart');
      expect(provider.contains('List<Song> _favoritesCache'), isTrue,
          reason: 'favorites is read on every collections build');
      expect(provider.contains('songs.where((s) => s.isFavorite).toList();'),
          isTrue);
      // Dead code that only allocated: nothing reads either getter.
      expect(provider.contains('get sortedByArtist'), isFalse);
      expect(provider.contains('get groupedByRegion'), isFalse);
    });

    test('the art cache touch is throttled per file', () {
      final art = read('lib/services/art_cache_service.dart');
      expect(art.contains('Map<String, DateTime> _lastTouchedAt'), isTrue,
          reason: 'one setLastModified syscall per tile init is too many');
      expect(art.contains('_touchInterval'), isTrue);
    });

    test('missing art and lyrics filters are cached per version', () {
      final art = read('lib/screens/missing_art_screen.dart');
      expect(art.contains('int _missingVersion'), isTrue);
      final lyrics = read('lib/screens/missing_lyrics_screen.dart');
      expect(lyrics.contains('int _missingVersion'), isTrue);
    });
  });
}
