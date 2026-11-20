import 'package:flutter_test/flutter_test.dart';
import 'package:swara/utils/lrc.dart';

// Unit tests for the pure LRC parser in lib/utils/lrc.dart.
// parseLrc touches no platform channels, DB, or network, so these run
// on any host without extra setup.
void main() {
  group('parseLrc', () {
    test('parses simple timestamped lines', () {
      final lines = parseLrc('[00:12.00]Hello\n[00:15.30]World');
      expect(lines.length, 2);
      expect(lines[0].timeMs, 12000);
      expect(lines[0].text, 'Hello');
      expect(lines[1].timeMs, 15300);
      expect(lines[1].text, 'World');
    });

    test('supports multiple timestamps on one line', () {
      final lines = parseLrc('[00:10.00][00:20.00]Chorus');
      expect(lines.length, 2);
      expect(lines[0].timeMs, 10000);
      expect(lines[1].timeMs, 20000);
      expect(lines[0].text, 'Chorus');
      expect(lines[1].text, 'Chorus');
    });

    test('clamps negative timestamps to zero', () {
      final lines = parseLrc('[offset:-5000]\n[00:00.50]Too early');
      expect(lines.length, 1);
      expect(lines[0].timeMs, 0);
      expect(lines[0].text, 'Too early');
    });

    test('supports centisecond fractions', () {
      final lines = parseLrc('[01:02.05]Centisecond');
      expect(lines.length, 1);
      expect(lines[0].timeMs, 1 * 60000 + 2 * 1000 + 50);
    });

    test('supports millisecond fractions', () {
      final lines = parseLrc('[01:02.123]Millisecond');
      expect(lines.length, 1);
      expect(lines[0].timeMs, 1 * 60000 + 2 * 1000 + 123);
    });

    test('supports single digit fractions and missing fractions', () {
      final lines = parseLrc('[01:02.5]Decisecond\n[01:05]No fraction');
      expect(lines.length, 2);
      expect(lines[0].timeMs, 1 * 60000 + 2 * 1000 + 500);
      expect(lines[1].timeMs, 1 * 60000 + 5 * 1000);
    });

    test('skips metadata tags', () {
      final lines = parseLrc(
        '[ar:Some Artist]\n'
        '[ti:Some Title]\n'
        '[al:Some Album]\n'
        '[length: 03:00]\n'
        '[00:10.00]Hi',
      );
      expect(lines.length, 1);
      expect(lines[0].text, 'Hi');
    });

    test('returns lines sorted by time', () {
      final lines = parseLrc('[00:30.00]Late\n[00:10.00]Early\n[00:20.00]Middle');
      expect(lines.map((l) => l.text).toList(), ['Early', 'Middle', 'Late']);
    });

    test('skips lines without timestamps and other odd lines', () {
      final lines = parseLrc(
        '\n'
        'just a comment with no timestamp\n'
        '[badtimestamp]junk\n'
        '[00:10.00]\n'
        '[00:12.00]   \n'
        '[00:15.00]Valid',
      );
      expect(lines.length, 1);
      expect(lines[0].timeMs, 15000);
      expect(lines[0].text, 'Valid');
    });
  });
}
