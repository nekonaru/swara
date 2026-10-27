import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swara/utils/lrc.dart';

/// Regression tests for the MEDIUM batch.
void main() {
  group('LRC offset', () {
    test('an offset tag shifts every timestamp', () {
      final lines = parseLrc('[offset:+500]\n[00:10.00]first\n[00:20.00]second');
      expect(lines.length, 2);
      // Positive offset means the lyrics should appear later.
      expect(lines[0].timeMs, 10500);
      expect(lines[1].timeMs, 20500);
    });

    test('a negative offset is applied too', () {
      final lines = parseLrc('[offset:-300]\n[00:10.00]first');
      expect(lines.single.timeMs, 9700);
    });

    test('spaces inside the tag are tolerated', () {
      expect(parseLrcOffsetMs(['[offset : 250 ]']), 250);
      expect(parseLrcOffsetMs(['  [offset:+250]']), 250);
    });

    test('no offset tag means the original timing', () {
      final lines = parseLrc('[00:10.00]first\n[00:20.50]second');
      expect(lines[0].timeMs, 10000);
      expect(lines[1].timeMs, 20500);
      expect(parseLrcOffsetMs(['[ar:someone]']), isNull);
    });

    test('the first offset tag wins', () {
      expect(
        parseLrcOffsetMs(['[offset:100]', '[offset:900]']),
        100,
      );
    });

    test('timings stay sorted after an offset', () {
      final lines = parseLrc('[offset:-200]\n[00:20.00]b\n[00:10.00]a');
      expect(lines[0].text, 'a');
      expect(lines[1].text, 'b');
    });
  });

  group('source guards', () {
    String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

    test('smart shuffle seeds the last played stamps from the database', () {
      final player = read('lib/services/player_service.dart');
      expect(
        player.contains('getLastPlayedStamps'),
        isTrue,
        reason: 'without this the staleness half of smart shuffle is dead '
            'every time the app restarts',
      );
    });

    test('equalizer applies are serialized and throttled', () {
      final eq = read('lib/services/equalizer_service.dart');
      expect(eq.contains('_scheduleApply'), isTrue);
      expect(eq.contains('_chain'), isTrue);
      // Never await the plugin calls that never reply.
      expect(eq.contains('await _run(() => EqualizerFlutter.'), isFalse);
    });

    test('the media handler stop does not tear the handler down', () {
      final handler = read('lib/services/swara_audio_handler.dart');
      final stopIndex = handler.indexOf('Future<void> stop()');
      expect(stopIndex, greaterThan(-1));
      final end = handler.indexOf('\n  }', stopIndex);
      final body = handler.substring(
          stopIndex, end > stopIndex ? end : handler.length);
      expect(
        body.contains('disposeHandler()'),
        isFalse,
        reason: 'disposing the listener here froze the notification forever',
      );
      expect(body.contains('_syncState()'), isTrue);
    });

    test('playlist collage is built off the UI isolate with a fingerprint', () {
      final art = read('lib/services/playlist_art_service.dart');
      expect(art.contains('Isolate.run'), isTrue);
      expect(
        art.contains('_builtCounts'),
        isFalse,
        reason: 'a song count guard kept stale collages forever',
      );
      expect(art.contains('fingerprintOf'), isTrue);
    });

    test('dashboard hides songs from hidden folders', () {
      final dash = read('lib/screens/dashboard_screen.dart');
      final start = dash.indexOf('Future<void> _load');
      final body = dash.substring(start, start + 4000);
      expect(body.contains('getExcludedFolders'), isTrue);
    });

    test('theme writes are serialized', () {
      final theme = read('lib/providers/theme_provider.dart');
      expect(theme.contains('_writeChain'), isTrue);
      // setTextScale must validate against the same whitelist load() uses.
      final start = theme.indexOf('Future<void> setTextScale');
      expect(theme.substring(start, start + 300).contains('kTextScales.contains'),
          isTrue);
    });
  });
}