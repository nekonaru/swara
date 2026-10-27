import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guards for bugs found while verifying existing features.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  group('crossfade', () {
    test('the natural completion listener ignores a running fade', () {
      final player = read('lib/services/player_service.dart');
      // Without this guard the track completed in the middle of its own fade,
      // called next(), bumped the play generation and aborted the fade loop.
      expect(
        player.contains('_crossfadeActiveGeneration == -1) {'),
        isTrue,
        reason: 'the completion listener must skip while a fade is in flight',
      );
      expect(
        player.contains('_abortCrossfadeForQueueEdit'),
        isTrue,
        reason: 'queue edits must drop a pending fade whose target index is '
            'about to be invalidated',
      );
    });

    test('repeat one stops the standby player', () {
      final player = read('lib/services/player_service.dart');
      expect(
        player.contains('_stopStandbyPlayer()'),
        isTrue,
        reason: 'a cancelled fade must not leave the other player audible',
      );
    });
  });

  group('equalizer', () {
    test('band levels are sent in dB, not millibels', () {
      final eq = read('lib/services/equalizer_service.dart');
      // The plugin multiplies by 100 on its own, so multiplying here asked
      // the device for +40 dB and every band threw IllegalArgumentException.
      expect(eq.contains('gains[i] * 100'), isFalse);
      expect(eq.contains('clamp(minDb.toDouble(), maxDb.toDouble())'), isTrue);
    });

    test('the plugin calls that never reply are not awaited', () {
      final eq = read('lib/services/equalizer_service.dart');
      // equalizer_flutter 0.0.1 never calls result.success for init, enable,
      // release, setBandLevel or setPreset, so awaiting them always timed out
      // and left the equalizer permanently disabled.
      expect(
        eq.contains('await _run(() => EqualizerFlutter.init'),
        isFalse,
        reason: 'init must be fired without awaiting',
      );
      expect(eq.contains("'probe freqs'"), isTrue,
          reason: 'readiness must be probed with a call that replies');
    });
  });

  group('duplicate finder', () {
    test('grouping key includes album and duration', () {
      final dupes = read('lib/screens/duplicates_screen.dart');
      // Title plus artist alone grouped a studio track with a live version,
      // and the bulk delete then removed a different recording along with its
      // playlist entries and history.
      expect(dupes.contains('isSameRecording'), isTrue);
      expect(dupes.contains('duplicateGroupKey(\n    song.title'), isTrue);
    });
  });

  group('bulk edit', () {
    test('writes in one batch and reloads once', () {
      final bulk = read('lib/screens/bulk_edit_screen.dart');
      expect(bulk.contains('updateSongMetadataBulk'), isTrue);
      final db = read('lib/services/db_helper.dart');
      expect(db.contains('Future<void> updateSongMetadataBulk'), isTrue);
    });
  });

  group('auto playlists', () {
    test('re-sync when the library changes', () {
      final collections = read('lib/screens/collections_screen.dart');
      expect(
        collections.contains('_autoSyncedVersion'),
        isTrue,
        reason: 'Daily Mix and Unplayed must follow hiding a folder or a rescan',
      );
    });
  });

  group('hidden folders', () {
    test('most played respects excluded folders', () {
      final provider = read('lib/providers/library_provider.dart');
      expect(
        provider.contains('Future<List<Song>> getMostPlayed'),
        isTrue,
      );
      final start = provider.indexOf('Future<List<Song>> getMostPlayed');
      expect(start, greaterThan(-1));
      final end = provider.indexOf('\n  }', start);
      final body =
          provider.substring(start, end > start ? end : start + 600);
      expect(body.contains('getExcludedFolders'), isTrue);
    });
  });
}