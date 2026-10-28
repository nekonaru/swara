import 'package:flutter_test/flutter_test.dart';
import 'package:swara/models/song.dart';

// Tests for the transparent gzip codec used for the lyrics DB column.
// These tests use only pure dart:convert logic, so they run on any host.
void main() {
  Song makeSong(String? lyrics) {
    return Song(
      id: 1,
      filePath: '/music/song.mp3',
      title: 'Title',
      artist: 'Artist',
      album: 'Album',
      lyrics: lyrics,
    );
  }

  group('encodeLyricsForDb', () {
    test('returns null for null input', () {
      expect(encodeLyricsForDb(null), isNull);
    });

    test('returns empty string for empty input', () {
      expect(encodeLyricsForDb(''), '');
    });

    test('encodes short lyrics with gz: marker', () {
      final String? encoded = encodeLyricsForDb('hello world');
      expect(encoded, isNotNull);
      expect(encoded, startsWith('gz:'));
    });
  });

  group('decodeLyricsFromDb roundtrip', () {
    test('roundtrips short lyrics', () {
      const String lyrics = 'hello world';
      expect(decodeLyricsFromDb(encodeLyricsForDb(lyrics)), lyrics);
    });

    test('roundtrips long lyrics', () {
      final String lyrics = List.filled(500, 'Lorem ipsum dolor sit amet. ').join();
      final String? encoded = encodeLyricsForDb(lyrics);
      expect(encoded, startsWith('gz:'));
      expect(decodeLyricsFromDb(encoded), lyrics);
    });

    test('roundtrips unicode lyrics', () {
      const String lyrics = 'Bahasa Indonesia: halo dunia\n'
          'Japanese: \u3053\u3093\u306b\u3061\u306f\u4e16\u754c\n'
          'Arabic: \u0645\u0631\u062d\u0628\u0627 \u0628\u0627\u0644\u0639\u0627\u0644\u0645\n'
          'Accents: caf\u00e9 na\u00efve r\u00e9sum\u00e9 \u4e2d\u6587\u6b4c\u66f2';
      expect(decodeLyricsFromDb(encodeLyricsForDb(lyrics)), lyrics);
    });

    test('roundtrips emoji lyrics', () {
      const String lyrics = 'Music is fun \u266a\u266b\nLine two here \u{1F3B5}\u{1F3A7}\u{1F49c}';
      expect(decodeLyricsFromDb(encodeLyricsForDb(lyrics)), lyrics);
    });

    test('keeps null as null', () {
      expect(decodeLyricsFromDb(null), isNull);
      expect(decodeLyricsFromDb(encodeLyricsForDb(null)), isNull);
    });

    test('keeps empty string as empty string', () {
      expect(decodeLyricsFromDb(''), '');
      expect(decodeLyricsFromDb(encodeLyricsForDb('')), '');
    });
  });

  group('decodeLyricsFromDb compatibility', () {
    test('legacy plaintext passes through unchanged', () {
      const String legacy = 'just plain lyrics\nsecond line';
      expect(decodeLyricsFromDb(legacy), legacy);
    });

    test('string without gz marker passes through unchanged', () {
      const String value = 'gz without colon prefix is intact';
      expect(decodeLyricsFromDb(value), value);
    });

    test('corrupt gz payload returns original without throwing', () {
      const String corruptBase64 = 'gz:!!!not-base64!!!';
      expect(() => decodeLyricsFromDb(corruptBase64), returnsNormally);
      expect(decodeLyricsFromDb(corruptBase64), corruptBase64);
    });

    test('non gzip base64 payload returns original without throwing', () {
      // 'aGVsbG8=' is base64 for "hello", which is not gzip data.
      const String notGzip = 'gz:aGVsbG8=';
      expect(() => decodeLyricsFromDb(notGzip), returnsNormally);
      expect(decodeLyricsFromDb(notGzip), notGzip);
    });
  });

  group('Song toMap/fromMap lyrics roundtrip', () {
    test('preserves short lyrics', () {
      final Song song = makeSong('hello world');
      final Map<String, dynamic> map = song.toMap();
      expect(map['lyrics'], startsWith('gz:'));
      final Song restored = Song.fromMap(map);
      expect(restored.lyrics, 'hello world');
    });

    test('preserves long unicode and emoji lyrics', () {
      final String lyrics =
          '${List.filled(200, 'La la la \u266a ').join()}end \u{1F3B5}\u4e2d\u6587';
      final Song song = makeSong(lyrics);
      final Song restored = Song.fromMap(song.toMap());
      expect(restored.lyrics, lyrics);
    });

    test('preserves null lyrics', () {
      final Song song = makeSong(null);
      final Map<String, dynamic> map = song.toMap();
      expect(map['lyrics'], isNull);
      expect(Song.fromMap(map).lyrics, isNull);
    });

    test('preserves empty lyrics', () {
      final Song song = makeSong('');
      final Map<String, dynamic> map = song.toMap();
      expect(map['lyrics'], '');
      expect(Song.fromMap(map).lyrics, '');
    });

    test('reads legacy plaintext lyrics row unchanged', () {
      final Song song = makeSong('legacy plain lyrics');
      final Map<String, dynamic> legacyMap = song.toMap();
      legacyMap['lyrics'] = 'legacy plain lyrics';
      expect(Song.fromMap(legacyMap).lyrics, 'legacy plain lyrics');
    });
  });

  // A row with an empty or invalid filePath cannot be played, so fromMap
  // rejects it with a FormatException. The DB loaders must therefore skip
  // such rows (see DBHelper._songsFromRows) instead of letting one bad row
  // blank the whole library. These tests pin that contract.
  group('Song.fromMap rejects corrupt rows', () {
    test('throws FormatException on empty filePath', () {
      final Map<String, dynamic> map = makeSong(null).toMap();
      map['filePath'] = '';
      expect(() => Song.fromMap(map), throwsFormatException);
    });

    test('throws FormatException on non-int id', () {
      final Map<String, dynamic> map = makeSong(null).toMap();
      map['id'] = 'not-an-int';
      expect(() => Song.fromMap(map), throwsFormatException);
    });

    test('accepts a valid row with a real path', () {
      final Map<String, dynamic> map = makeSong(null).toMap();
      map['filePath'] = '/storage/emulated/0/Music/song.mp3';
      expect(Song.fromMap(map).filePath, '/storage/emulated/0/Music/song.mp3');
    });
  });
}
