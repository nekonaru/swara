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
    test('band levels are clamped to the device reported range', () {
      final eq = read('lib/services/equalizer_service.dart');
      // The native android.media.audiofx.Equalizer takes millibels and each
      // device reports its own usable range. The old plugin took dB and
      // multiplied by 100 itself, and asking for +40 dB made every band
      // throw. Here every band written must be clamped to the range the
      // device reports at attach time.
      expect(eq.contains('clamp(minLevelMb, maxLevelMb)'), isTrue);
      expect(eq.contains('gains[i] * 100'), isTrue);
    });

    test('attach goes through the native DSP effect, not a dead plugin', () {
      final eq = read('lib/services/equalizer_service.dart');
      // equalizer_flutter 0.0.1 never calls result.success for init, enable,
      // release, setBandLevel or setPreset, so awaiting them always timed
      // out and the equalizer never reached the audio. The rewrite must
      // attach the native effect and read back the device band count and
      // range before writing gains.
      expect(eq.contains('attachEqualizer'), isTrue);
      expect(eq.contains('getEqualizerInfo'), isTrue);
      expect(eq.contains('EqualizerFlutter'), isFalse);
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