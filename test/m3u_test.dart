import 'package:flutter_test/flutter_test.dart';
import 'package:swara/models/song.dart';
import 'package:swara/services/m3u_service.dart';

Song _song(int id, String path) => Song(
      id: id,
      filePath: path,
      title: 'Title$id',
      artist: 'Artist',
      album: 'Album',
      durationMs: 1000,
    );

void main() {
  group('M3uService.matchContent', () {
    test('matches an absolute path exactly', () {
      final library = [_song(1, '/music/a/one.mp3'), _song(2, '/music/b/two.mp3')];
      final result = M3uService.matchContent(
        content: '/music/a/one.mp3\n/music/b/two.mp3',
        baseDir: '/music',
        library: library,
      );
      expect(result.matched.map((s) => s.id), [1, 2]);
      expect(result.unresolved, 0);
    });

    test('resolves a relative entry against the m3u folder', () {
      final library = [_song(1, '/music/one.mp3')];
      final result = M3uService.matchContent(
        content: 'one.mp3',
        baseDir: '/music',
        library: library,
      );
      expect(result.matched.single.id, 1);
    });

    test('decodes a file:// uri', () {
      final library = [_song(7, '/music/a/seven.mp3')];
      final result = M3uService.matchContent(
        content: 'file:///music/a/seven.mp3',
        baseDir: '/music',
        library: library,
      );
      expect(result.matched.single.id, 7);
    });

    test('ignores comments and #EXTINF lines', () {
      final library = [_song(1, '/music/one.mp3')];
      final result = M3uService.matchContent(
        content: '#EXTM3U\n#EXTINF:123,Artist - Title\n/music/one.mp3\n',
        baseDir: '/music',
        library: library,
      );
      expect(result.matched.single.id, 1);
      expect(result.unresolved, 0);
    });

    test('keeps one copy when the same song is listed twice', () {
      final library = [_song(1, '/music/one.mp3')];
      final result = M3uService.matchContent(
        content: '/music/one.mp3\n/music/one.mp3\n',
        baseDir: '/music',
        library: library,
      );
      expect(result.matched.length, 1);
    });

    test('reports a missing file instead of guessing', () {
      final library = [_song(1, '/music/one.mp3')];
      final result = M3uService.matchContent(
        content: '/music/gone.mp3',
        baseDir: '/music',
        library: library,
      );
      expect(result.matched, isEmpty);
      expect(result.missing, 1);
      expect(result.ambiguous, 0);
    });

    // Regression: the file name fallback used to return the FIRST library
    // song with a matching base name, so an M3U could silently add the wrong
    // track. An ambiguous name must be reported, never guessed.
    test('reports an ambiguous file name instead of picking the first song', () {
      final library = [
        _song(1, '/music/albumA/track.mp3'),
        _song(2, '/music/albumB/track.mp3'),
      ];
      final result = M3uService.matchContent(
        content: 'track.mp3',
        baseDir: '/music',
        library: library,
      );
      expect(result.matched, isEmpty);
      expect(result.ambiguous, 1);
      expect(result.missing, 0);
      expect(result.unresolved, 1);
    });

    test('an exact path still wins when the name is ambiguous', () {
      final library = [
        _song(1, '/music/albumA/track.mp3'),
        _song(2, '/music/albumB/track.mp3'),
      ];
      final result = M3uService.matchContent(
        content: '/music/albumB/track.mp3',
        baseDir: '/music',
        library: library,
      );
      expect(result.matched.single.id, 2);
      expect(result.unresolved, 0);
    });

    test('a unique file name still matches through the fallback', () {
      final library = [
        _song(1, '/music/albumA/track.mp3'),
        _song(2, '/music/albumB/other.mp3'),
      ];
      final result = M3uService.matchContent(
        content: 'other.mp3',
        baseDir: '/music',
        library: library,
      );
      expect(result.matched.single.id, 2);
      expect(result.unresolved, 0);
    });
  });
}