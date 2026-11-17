import 'package:flutter_test/flutter_test.dart';
import 'package:swara/utils/format.dart';

// Unit tests for pure formatting and sorting helpers in lib/utils/format.dart.
// No platform channels are used here, so these tests run on any host.
void main() {
  group('folderOf', () {
    test('returns parent folder for slash path', () {
      expect(folderOf('/storage/music/song.mp3'), '/storage/music');
    });

    test('supports backslash path and normalizes to slashes', () {
      expect(folderOf(r'C:\Music\Rock\song.mp3'), 'C:/Music/Rock');
    });

    test('supports mixed separators', () {
      expect(folderOf(r'C:\Music/Rock\song.mp3'), 'C:/Music/Rock');
    });

    test('returns empty string when there is no separator', () {
      expect(folderOf('song.mp3'), '');
    });

    test('returns empty string for empty input', () {
      expect(folderOf(''), '');
    });

    test('returns empty string for root slash', () {
      expect(folderOf('/'), '');
    });

    test('handles trailing slash by returning the part before it', () {
      expect(folderOf('music/'), 'music');
    });

    test('handles doubled separators in weird paths', () {
      expect(folderOf('/music//albums//song.mp3'), '/music//albums/');
    });
  });

  group('safeInitial', () {
    test('returns hash for empty string', () {
      expect(safeInitial(''), '#');
    });

    test('uppercases a lowercase first letter', () {
      expect(safeInitial('hello'), 'H');
    });

    test('uppercases a single lowercase char', () {
      expect(safeInitial('a'), 'A');
    });

    test('keeps an uppercase first letter as is', () {
      expect(safeInitial('Zebra'), 'Z');
    });

    test('returns digit first char unchanged', () {
      expect(safeInitial('1song'), '1');
    });

    test('returns symbol first char unchanged', () {
      expect(safeInitial('#mix'), '#');
    });

    test('returns non-latin first char unchanged', () {
      expect(safeInitial('さくら'), 'さ');
    });

    test('returns CJK first char unchanged', () {
      expect(safeInitial('中文歌曲'), '中');
    });
  });

  group('compareTitles sorts symbols before digits before latin before CJK', () {
    test('symbol sorts before digit', () {
      expect(compareTitles('#mix', '1 song'), lessThan(0));
      expect(compareTitles('1 song', '#mix'), greaterThan(0));
    });

    test('digit sorts before latin letter', () {
      expect(compareTitles('1 song', 'Apple'), lessThan(0));
      expect(compareTitles('Apple', '1 song'), greaterThan(0));
    });

    test('latin letter sorts before CJK', () {
      expect(compareTitles('Zebra', 'さくら'), lessThan(0));
      expect(compareTitles('さくら', 'Zebra'), greaterThan(0));
    });

    test('symbol sorts before CJK', () {
      expect(compareTitles('#mix', '中文歌曲'), lessThan(0));
    });

    test('digit sorts before CJK', () {
      expect(compareTitles('2 songs', '日本語'), lessThan(0));
    });

    test('same title with different case compares as equal', () {
      expect(compareTitles('Apple', 'apple'), 0);
    });

    test('orders titles inside the same tier alphabetically', () {
      expect(compareTitles('apple', 'Banana'), lessThan(0));
      expect(compareTitles('Banana', 'apple'), greaterThan(0));
    });

    test('empty string sorts before digit titles', () {
      expect(compareTitles('', '1 song'), lessThan(0));
    });
  });

  group('formatDuration', () {
    test('formats zero as 00:00', () {
      expect(formatDuration(0), '00:00');
    });

    test('formats one second', () {
      expect(formatDuration(1000), '00:01');
    });

    test('formats seconds only', () {
      expect(formatDuration(59000), '00:59');
    });

    test('formats whole minutes', () {
      expect(formatDuration(60000), '01:00');
    });

    test('formats ten minutes', () {
      expect(formatDuration(600000), '10:00');
    });

    test('formats exact hour without minutes and seconds', () {
      expect(formatDuration(3600000), '1:00:00');
    });

    test('formats hour plus minutes plus seconds', () {
      // 3723000 ms is 1 hour, 2 minutes, 3 seconds.
      expect(formatDuration(3723000), '1:02:03');
    });
  });

  group('formatDurationLong', () {
    test('formats zero as 45m', () {
      expect(formatDurationLong(0), '0m');
    });

    test('rounds sub minute durations to 1m', () {
      // 45 seconds rounds to 1 minute.
      expect(formatDurationLong(45000), '1m');
    });

    test('formats minutes only', () {
      expect(formatDurationLong(2700000), '45m');
    });

    test('formats exact hour without leftover minutes', () {
      expect(formatDurationLong(3600000), '1h');
    });

    test('formats hour plus minutes', () {
      expect(formatDurationLong(5400000), '1h 30m');
    });

    test('formats multiple hours plus minutes', () {
      // 8100000 ms is 135 minutes, which is 2 hours 15 minutes.
      expect(formatDurationLong(8100000), '2h 15m');
    });

    test('indonesian renders jam/menit', () {
      expect(formatDurationLong(0, indonesian: true), '0 menit');
      expect(formatDurationLong(45000, indonesian: true), '1 menit');
      expect(formatDurationLong(2700000, indonesian: true), '45 menit');
      expect(formatDurationLong(3600000, indonesian: true), '1 jam');
      expect(formatDurationLong(5400000, indonesian: true), '1 jam 30 menit');
      expect(formatDurationLong(8100000, indonesian: true), '2 jam 15 menit');
    });
  });
}
