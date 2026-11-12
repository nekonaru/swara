import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin Dart facade over the native audio effect helpers on
/// `swara/audio_effects` (see SwaraAudioEffects.kt).
///
/// Holds the only MethodChannel, forwards calls, and routes the one native
/// push event (onAudioBecomingNoisy) to whoever registered for it.
class AudioEffectsService {
  AudioEffectsService._() {
    _channel.setMethodCallHandler(_onNativeCall);
  }
  static final AudioEffectsService instance = AudioEffectsService._();

  static const String channelName = 'swara/audio_effects';
  final MethodChannel _channel = const MethodChannel(channelName);

  // Handlers for the single native push event. Keyed by event so the
  // registration itself is idempotent; the last registered handler wins.
  final Map<String, void Function()> _handlers = <String, void Function()>{};

  /// Register for a native push event such as "onAudioBecomingNoisy".
  void onEvent(String event, void Function() handler) {
    _handlers[event] = handler;
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('AudioEffects $method failed: $e');
      return null;
    } on MissingPluginException catch (e) {
      debugPrint('AudioEffects $method not available: $e');
      return null;
    }
  }

  Future<bool> openAudioEffectSession(int? sessionId) async {
    if (sessionId == null || sessionId <= 0) return false;
    await _invoke<void>('openAudioEffectSession', {'sessionId': sessionId});
    return true;
  }

  Future<bool> closeAudioEffectSession(int? sessionId) async {
    if (sessionId == null || sessionId <= 0) return false;
    await _invoke<void>('closeAudioEffectSession', {'sessionId': sessionId});
    return true;
  }

  /// Ask the system to show its equalizer panel for [sessionId]. Returns
  /// false when no equalizer app is installed or the panel cannot start.
  Future<bool> openEqualizerPanel(int? sessionId) async {
    if (sessionId == null || sessionId <= 0) return false;
    return (await _invoke<bool>('openEqualizerPanel', {'sessionId': sessionId})) ?? false;
  }

  /// Attach the system DSP equalizer to [sessionId]. Returns whether the
  /// effect is attached after the call.
  Future<bool> attachEqualizer(int sessionId) async {
    return (await _invoke<bool>('attachEqualizer', {'sessionId': sessionId})) ?? false;
  }

  Future<void> releaseEqualizer() async {
    await _invoke<void>('releaseEqualizer');
  }

  /// Device reported capabilities for the attached effect, or null when the
  /// effect is not attached or the device cannot report them.
  Future<Map<String, dynamic>?> getEqualizerInfo() async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getEqualizerInfo');
    if (raw == null) return null;
    return <String, dynamic>{
      'bands': (raw['bands'] as num?)?.toInt() ?? 5,
      'minLevelMilliBels': (raw['minLevelMilliBels'] as num?)?.toInt() ?? -1500,
      'maxLevelMilliBels': (raw['maxLevelMilliBels'] as num?)?.toInt() ?? 1500,
      'centerFreqsMilliHz':
          (raw['centerFreqsMilliHz'] as List?)?.map((e) => (e as num).toInt()).toList() ??
              const <int>[],
    };
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    await _invoke<void>('setEqualizerEnabled', {'enabled': enabled});
  }

  Future<void> setBandLevel(int band, int milliBels) async {
    await _invoke<void>('setBandLevel', {'band': band, 'milliBels': milliBels});
  }

  Future<void> registerNoisyListener() async {
    await _invoke<void>('registerNoisyListener');
  }

  Future<void> unregisterNoisyListener() async {
    await _invoke<void>('unregisterNoisyListener');
  }

  /// The device's supported ABIs (64-bit first), e.g. [arm64-v8a, armeabi-v7a].
  /// Used to pick the right split APK for an in-app update.
  Future<List<String>> deviceAbi() async {
    final raw = await _invoke<List<dynamic>>('deviceAbi');
    if (raw == null) return const <String>[];
    return raw.map((e) => e.toString()).toList();
  }

  /// Hand a downloaded APK to the system package installer. Returns
  /// "ok" when the installer intent launched, "no_permission" when the
  /// per-app "Install unknown apps" grant screen was opened instead (the
  /// user must enable it once and tap the update again), or "error".
  Future<String> installApk(String path) async {
    return (await _invoke<String>('installApk', {'path': path})) ?? 'error';
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    final handler = _handlers[call.method];
    if (handler != null) handler();
  }
}
