import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the intro/motion redesign and the v4.0 feature batch.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  group('intro handoff', () {
    test('a single gate replaces the second spinner stage', () {
      final main = read('lib/main.dart');
      expect(main.contains('class StartupGate'), isFalse);
      expect(main.contains('Future<bool> bootFuture'), isTrue);
      expect(main.contains("const SplashScreen(key: ValueKey('splash'))"), isTrue);
      expect(main.contains('Duration(milliseconds: 600)'), isTrue);
    });

    test('permissions are asked after the intro', () {
      final main = read('lib/main.dart');
      expect(main.contains('Permission.audio.request()'), isFalse);
      expect(
          main.contains('PermissionService.ensureEssentialPermissions()'), isTrue);
      final onboarding = read('lib/screens/onboarding_screen.dart');
      expect(onboarding.contains('PermissionService.ensureEssentialPermissions()'),
          isTrue);
      expect(onboarding.contains('_kOnboardingPageKey'), isTrue);
    });

    test('native splash crossfades and legacy splash has a glyph', () {
      final activity = read(
          'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/MainActivity.kt');
      expect(activity.contains('setOnExitAnimationListener'), isTrue);
      final legacy =
          read('android/app/src/main/res/drawable/splash_background.xml');
      expect(legacy.contains('@drawable/ic_splash_icon'), isTrue);
      final plain =
          read('android/app/src/main/res/drawable/launch_background.xml');
      expect(plain.contains('@drawable/ic_splash_icon'), isFalse);
      final splash = read('lib/screens/splash_screen.dart');
      expect(splash.contains('assets/swara_splash_glyph.png'), isTrue);
      final night = read('android/app/src/main/res/values-night/styles.xml');
      expect(night.contains('@drawable/splash_background'), isTrue);
    });
  });

  group('smooth motion', () {
    test('splash uses paint-only transitions and a shared controller', () {
      final splash = read('lib/screens/splash_screen.dart');
      expect(splash.contains('FadeTransition'), isTrue);
      expect(splash.contains('Transform.scale('), isTrue);
      expect(splash.contains('didChangeDependencies'), isTrue);
      expect(splash.contains('late final AnimationController _entrance'), isTrue);
    });

    test('reduce motion is honoured in one shared place', () {
      final motion = read('lib/utils/motion.dart');
      expect(motion.contains('disableAnimations'), isTrue);
      final theme = read('lib/theme/app_theme.dart');
      expect(theme.contains('reduceMotion(context)'), isTrue);
      final fade = read('lib/widgets/entrance_fade.dart');
      expect(fade.contains('reduceMotion(context)'), isTrue);
      final transitions = read('lib/utils/page_transitions.dart');
      expect(transitions.contains('reduceMotion(context)'), isTrue);
    });
  });

  group('native playback correctness', () {
    test('interruptions are handled once by Swara', () {
      final player = read('lib/services/player_service.dart');
      expect(player.contains('AudioPlayer(handleInterruptions: false)'), isTrue);
      expect(player.contains('unawaited(togglePlayPause());'), isFalse);
      expect(player.contains('Future<void> pausePlayback()'), isTrue);
      final handler = read('lib/services/swara_audio_handler.dart');
      expect(handler.contains('ps.pausePlayback()'), isTrue);
    });

    test('crossfade enabled survives a restart', () {
      final player = read('lib/services/player_service.dart');
      expect(player.contains('_prefsCrossfadeEnabledKey'), isTrue);
      expect(player.contains('prefs.getBool(_prefsCrossfadeEnabledKey)'), isTrue);
    });
  });

  group('new features', () {
    test('named EQ presets are stored and applied', () {
      final theme = read('lib/providers/theme_provider.dart');
      expect(theme.contains('List<EqPreset> eqPresets'), isTrue);
      expect(theme.contains('user:'), isTrue);
      final controls = read('lib/widgets/eq_controls.dart');
      expect(controls.contains('eqPresetSave'), isTrue);
      final service = read('lib/services/equalizer_service.dart');
      expect(service.contains('presetToken'), isTrue);
    });

    test('Quick Settings tile drives the MediaSession natively', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest.contains('SwaraPlaybackTile'), isTrue);
      expect(manifest.contains('BIND_QUICK_SETTINGS_TILE'), isTrue);
      expect(manifest.contains('QS_TILE'), isTrue);
      final tile = read(
          'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraPlaybackTile.kt');
      expect(tile.contains('TileService'), isTrue);
      expect(tile.contains('transportControls'), isTrue);
      expect(tile.contains('KEYCODE_MEDIA_PLAY_PAUSE'), isTrue);
    });
  });
}
