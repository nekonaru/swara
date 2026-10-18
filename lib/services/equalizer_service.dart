import 'dart:async';

import 'package:equalizer_flutter/equalizer_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Resample a 5-band EQ curve to [bandCount] device bands.
///
/// Pure linear interpolation so it is unit testable. [curve] holds
/// relative dB gains from the lowest to the highest band.
List<double> resampleCurve(List<double> curve, int bandCount) {
  if (curve.isEmpty || bandCount <= 0) return List.filled(bandCount, 0);
  if (bandCount == 1) {
    final avg = curve.reduce((a, b) => a + b) / curve.length;
    return [avg];
  }
  final out = <double>[];
  for (int i = 0; i < bandCount; i++) {
    final pos = i * (curve.length - 1) / (bandCount - 1);
    final lo = pos.floor().clamp(0, curve.length - 1);
    final hi = pos.ceil().clamp(0, curve.length - 1);
    final frac = pos - lo;
    out.add(curve[lo] * (1 - frac) + curve[hi] * frac);
  }
  return out;
}

/// Canonical 5-band curves (relative dB, low to high).
/// Must stay in sync with the EQ preset UI choices.
const Map<String, List<double>> kEqCurves = {
  'Flat': [0, 0, 0, 0, 0],
  'Pop': [1, 2, 2, 1, 0],
  'Rock': [3, 1, -1, 1, 3],
  'Classical': [2, 0, 0, 0, 2],
  'Jazz': [2, 1, 0, 1, 2],
  'Electronic': [3, 1, 0, 2, 3],
  'Hip-Hop': [3, 2, 0, 0, 1],
  'Bass Boost': [4, 3, 0, 0, 0],
  'Vocal': [-1, 0, 2, 2, 0],
  'Custom': [0, 0, 0, 0, 0],
};

/// Drives the Android system equalizer for the active audio session.
///
/// The effect is real DSP on the output mix, not a visualizer. The
/// underlying plugin is old and can hang on some devices, so EVERY
/// platform call goes through [_guard] with a timeout: a stuck call
/// degrades to flat sound instead of freezing the settings screen.
class EqualizerService {
  EqualizerService._();
  static final EqualizerService instance = EqualizerService._();

  /// A plugin call taking longer than this is treated as failed.
  /// Without this, one stuck method-channel call freezes preset
  /// switching until the settings screen is reopened.
  static const Duration _pluginTimeout = Duration(milliseconds: 2500);

  /// Slider drags fire roughly 60 events per second. Applying each one would
  /// queue a burst of platform calls and write to prefs on every frame, so
  /// requests that arrive inside this window collapse into one apply that uses
  /// the newest preset and gains. A trailing apply is always queued, so the
  /// value the user stops dragging at is never dropped.
  static const Duration _applyThrottle = Duration(milliseconds: 150);

  int? _sessionId;
  bool _ready = false;
  String _preset = 'Flat';
  // Live gains for the Custom preset, set via applyCustom.
  List<double> _customGains = [0, 0, 0, 0, 0];

  // Serializes band applications. Each apply is chained onto [_chain], so two
  // of them can never touch the platform at the same time.
  Future<void> _chain = Future<void>.value();
  // Applies currently queued or running, used by [_flushApply] to wait for
  // the pending work without polling.
  final Set<Future<void>> _inFlight = <Future<void>>{};
  Timer? _applyTimer;
  bool _applyQueued = false;

  String get preset => _preset;
  bool get isReady => _ready;

  // Send a command to the plugin WITHOUT waiting for its Future.
  //
  // equalizer_flutter 0.0.1 has an incomplete MethodChannel: the native
  // handler for init, enable, release, setBandLevel and setPreset never calls
  // result.success or result.error, so the Dart Future for those calls never
  // completes. Awaiting them always timed out, which left _ready false and
  // meant no gain ever reached the audio. Readiness is therefore probed with
  // getCenterBandFreqs, which does reply.
  void _fire(Future<void> Function() op, String what) {
    unawaited(op().timeout(_pluginTimeout).then<void>((_) {}).catchError((Object e) {
      debugPrint('Equalizer $what failed: $e');
    }));
  }

  Future<List<int>?> _getList(
      Future<List<int>> Function() op, String what) async {
    try {
      return await op().timeout(_pluginTimeout);
    } catch (e) {
      debugPrint('Equalizer $what failed: $e');
      return null;
    }
  }

  /// Request a band application, throttled.
  ///
  /// The timer restarts on every request, so a burst of slider events results
  /// in one single apply once the user pauses for [_applyThrottle]. Because
  /// [_applyBandsNow] reads [_preset] and [_customGains] at run time, that one
  /// apply always carries the last requested values (last write wins).
  void _scheduleApply() {
    _applyQueued = true;
    _applyTimer?.cancel();
    _applyTimer = Timer(_applyThrottle, _drainApply);
  }

  /// Hand the pending request to the serialization chain.
  void _drainApply() {
    _applyTimer?.cancel();
    _applyTimer = null;
    if (!_applyQueued) return;
    _applyQueued = false;
    final pending = _chain.then((_) => _applyBandsNow());
    _chain = pending.catchError((Object e) {
      debugPrint('Equalizer apply failed: $e');
    });
    _inFlight.add(pending);
    unawaited(pending.whenComplete(() => _inFlight.remove(pending)));
  }

  /// Force the pending apply out immediately and wait for it.
  ///
  /// Used by the callers that must be able to promise "the curve is applied
  /// when this returns" (attach, preset switch, slider release).
  Future<void> _flushApply() async {
    while (true) {
      if (_applyTimer != null || _applyQueued) _drainApply();
      if (_inFlight.isEmpty) return;
      await Future.wait(List<Future<void>>.of(_inFlight));
    }
  }

  /// Attach the effect to [player]'s audio session. Call after the
  /// player has a source (session id is null before that).
  /// Returns true when the effect is attached.
  Future<bool> attach(AudioPlayer player) async {
    final sessionId = player.androidAudioSessionId;
    if (sessionId == null) return false;
    if (_ready && sessionId == _sessionId) {
      _scheduleApply();
      await _flushApply();
      return true;
    }
    await release();
    // init never replies, so it is sent without awaiting and readiness is
    // confirmed through a call that does reply.
    _fire(() => EqualizerFlutter.init(sessionId), 'init');
    final probe = await _getList(
        () => EqualizerFlutter.getCenterBandFreqs(), 'probe freqs');
    if (probe == null || probe.isEmpty) {
      _ready = false;
      _sessionId = null;
      debugPrint('Equalizer: no usable band configuration on this device, '
          'the equalizer stays disabled.');
      return false;
    }
    _sessionId = sessionId;
    _ready = true;
    _scheduleApply();
    await _flushApply();
    return true;
  }

  /// Switch preset (persisted separately by ThemeProvider).
  Future<void> applyPreset(String name) async {
    _preset = name;
    if (!_ready) return;
    _scheduleApply();
    await _flushApply();
  }

  /// Apply user slider gains as the Custom preset. Always treated as a
  /// non Flat preset (effect enabled, resampled, bands set).
  Future<void> applyCustom(List<double> gains) async {
    _preset = 'Custom';
    _customGains = List<double>.generate(
        5, (i) => i < gains.length ? gains[i] : 0.0);
    if (!_ready) return;
    _scheduleApply();
    await _flushApply();
  }

  Future<void> _applyBandsNow() async {
    if (_preset == 'Flat') {
      _fire(() => EqualizerFlutter.setEnabled(false), 'disable');
      return;
    }
    _fire(() => EqualizerFlutter.setEnabled(true), 'enable');
    final List<double> curve;
    if (_preset == 'Custom') {
      curve = List.of(_customGains);
    } else {
      curve = kEqCurves[_preset] ?? kEqCurves['Flat']!;
    }
    var bandCount = 5;
    // getBandLevelRange is documented as dB, and setBandLevel takes dB too
    // (this plugin multiplies by 100 to reach native millibels). The previous
    // code multiplied by 100 as well, which asked the device for +40 dB and
    // made every band fail with IllegalArgumentException.
    var minDb = -15;
    var maxDb = 15;
    final range =
        await _getList(() => EqualizerFlutter.getBandLevelRange(), 'range');
    if (range != null && range.length >= 2) {
      minDb = range[0];
      maxDb = range[1];
    }
    final freqs = await _getList(
        () => EqualizerFlutter.getCenterBandFreqs(), 'freqs');
    if (freqs != null && freqs.isNotEmpty) bandCount = freqs.length;
    final gains = resampleCurve(curve, bandCount);
    for (int i = 0; i < bandCount; i++) {
      final db = gains[i].clamp(minDb.toDouble(), maxDb.toDouble()).round();
      _fire(() => EqualizerFlutter.setBandLevel(i, db), 'band $i');
    }
  }

  Future<void> release() async {
    // Drop a pending throttled apply, the effect is going away anyway.
    _applyTimer?.cancel();
    _applyTimer = null;
    _applyQueued = false;
    if (!_ready) return;
    _fire(() => EqualizerFlutter.release(), 'release');
    _ready = false;
    _sessionId = null;
  }
}
