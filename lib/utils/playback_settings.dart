import 'dart:math' as math;

/// A resolved playback setting for one song. Every field falls back from the
/// song override to the folder default and finally to a neutral global value.
class EffectivePlaybackSettings {
  final double gainDb;
  final int skipStartMs;
  final int skipEndMs;

  const EffectivePlaybackSettings({
    this.gainDb = 0,
    this.skipStartMs = 0,
    this.skipEndMs = 0,
  });

  /// Linear volume multiplier for [gainDb] (dB -> amplitude).
  double get volumeMultiplier => math.pow(10, gainDb / 20).toDouble().clamp(0.0, 1.0);

  static double _gain(dynamic raw) {
    final v = raw is num ? raw.toDouble() : 0.0;
    if (!v.isFinite) return 0;
    // A mild trim range: quiet tracks can be lifted, loud ones pulled down.
    return v.clamp(-12.0, 6.0);
  }

  static int _ms(dynamic raw) {
    final v = raw is num ? raw.toInt() : 0;
    return v < 0 ? 0 : v;
  }

  /// Resolve per-field with song > folder > global, then clamp the skip
  /// points to at most half the track and keep a 1s playable tail.
  static EffectivePlaybackSettings resolve({
    Map<String, num>? songOverride,
    Map<String, num>? folderOverride,
    Map<String, num>? globalDefault,
    int durationMs = 0,
  }) {
    num? pick(String key) => songOverride?[key] ??
        folderOverride?[key] ??
        globalDefault?[key];
    var gain = _gain(pick('gainDb'));
    var start = _ms(pick('skipStartMs'));
    var end = _ms(pick('skipEndMs'));
    if (durationMs > 0) {
      final half = durationMs ~/ 2;
      start = math.min(start, half);
      end = math.min(end, half);
      final tail = durationMs - 1000;
      if (tail > 0 && start + end > tail) {
        // Prefer the intro skip; trim the outro to keep playback finite.
        end = math.max(0, tail - start);
      }
    }
    return EffectivePlaybackSettings(
        gainDb: gain, skipStartMs: start, skipEndMs: end);
  }

  /// Folder path of a song, used to look up folder defaults.
  static String folderOf(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx < 0 ? '' : normalized.substring(0, idx);
  }
}
