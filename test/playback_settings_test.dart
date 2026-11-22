import 'package:flutter_test/flutter_test.dart';
import 'package:swara/utils/playback_settings.dart';

void main() {
  group('EffectivePlaybackSettings.resolve', () {
    test('per-field fallback song > folder > global', () {
      final s = EffectivePlaybackSettings.resolve(
        songOverride: {'gainDb': 3, 'skipStartMs': 5000},
        folderOverride: {'gainDb': -2, 'skipStartMs': 1000, 'skipEndMs': 2000},
        globalDefault: {'gainDb': 1, 'skipStartMs': 100, 'skipEndMs': 100},
        durationMs: 60000,
      );
      expect(s.gainDb, 3);
      expect(s.skipStartMs, 5000);
      expect(s.skipEndMs, 2000);
    });

    test('clamps range and keeps a one second tail', () {
      final s = EffectivePlaybackSettings.resolve(
        songOverride: {'gainDb': 99, 'skipStartMs': 90000, 'skipEndMs': 90000},
        durationMs: 100000,
      );
      expect(s.gainDb, 6);
      expect(s.skipStartMs, 50000);
      expect(s.skipEndMs, 49000);
      expect(s.skipStartMs + s.skipEndMs, lessThanOrEqualTo(99000));
    });

    test('corrupt values are ignored', () {
      final s = EffectivePlaybackSettings.resolve(
        songOverride: {'gainDb': double.nan, 'skipStartMs': -100},
        durationMs: 10000,
      );
      expect(s.gainDb, 0);
      expect(s.skipStartMs, 0);
    });

    test('dB to linear multiplier is bounded', () {
      expect(const EffectivePlaybackSettings(gainDb: 0).volumeMultiplier, closeTo(1, 0.001));
      expect(const EffectivePlaybackSettings(gainDb: -12).volumeMultiplier, lessThan(0.3));
      expect(const EffectivePlaybackSettings(gainDb: 6).volumeMultiplier, closeTo(1, 0.001));
    });

    test('folder path helper handles both separators', () {
      expect(EffectivePlaybackSettings.folderOf('/storage/Music/A.mp3'), '/storage/Music');
      expect(EffectivePlaybackSettings.folderOf('C:\\Music\\A.mp3'), 'C:/Music');
    });
  });
}
