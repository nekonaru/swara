import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_effects_service.dart';

/// Drives the native loudness normalizer (android.media.audiofx.LoudnessEnhancer)
/// on the active audio session. Kept separate from [EqualizerService] so the
/// two DSP effects can be toggled independently and neither blocks playback.
///
/// Every platform call is awaited with a timeout; a device that cannot create
/// the effect simply reports "not attached" and everything else keeps working.
class LoudnessService {
  LoudnessService._();
  static final LoudnessService instance = LoudnessService._();

  static const String prefsKey = 'loudness_enabled';
  static const Duration _pluginTimeout = Duration(milliseconds: 2500);

  final AudioEffectsService _native = AudioEffectsService.instance;
  bool _enabled = false;
  int? _sessionId;

  bool get enabled => _enabled;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(prefsKey) ?? false;
    } catch (e) {
      debugPrint('Loudness preference load failed: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, value);
    } catch (e) {
      debugPrint('Loudness preference save failed: $e');
    }
    if (!value) {
      _sessionId = null;
      try {
        await _native.releaseLoudness().timeout(_pluginTimeout);
      } catch (e) {
        debugPrint('Loudness release failed: $e');
      }
    }
  }

  /// Attach the effect to [player]'s session. Call after the player has a
  /// source. Returns true when the effect is attached.
  Future<bool> attach(AudioPlayer player) async {
    final sessionId = player.androidAudioSessionId;
    if (!_enabled || sessionId == null || sessionId <= 0) return false;
    if (_sessionId == sessionId) return true;
    try {
      final attached = await _native
          .attachLoudness(sessionId)
          .timeout(_pluginTimeout);
      if (attached != true) {
        _sessionId = null;
        return false;
      }
      _sessionId = sessionId;
      await _native.setLoudnessEnabled(true).timeout(_pluginTimeout);
      return true;
    } catch (e) {
      debugPrint('Loudness attach failed: $e');
      _sessionId = null;
      return false;
    }
  }

  Future<void> release() async {
    _sessionId = null;
    try {
      await _native.releaseLoudness().timeout(_pluginTimeout);
    } catch (e) {
      debugPrint('Loudness release failed: $e');
    }
  }
}
