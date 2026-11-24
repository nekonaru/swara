import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('splash uses the same flat glyph as the native splash', () {
    final splash = read('lib/screens/splash_screen.dart');
    expect(splash.contains('assets/swara_splash_glyph.png'), isTrue);
    expect(splash.contains('assets/swara-mark.png'), isFalse);
    final splashBg = read('android/app/src/main/res/drawable/splash_background.xml');
    expect(splashBg.contains('@drawable/ic_splash_icon'), isTrue);
    final plainBg = read('android/app/src/main/res/drawable/launch_background.xml');
    expect(plainBg.contains('@drawable/ic_splash_icon'), isFalse);
    final asset = File('assets/swara_splash_glyph.png');
    expect(asset.existsSync(), isTrue);
  });

  test('onboarding guards PageController before PageView attaches', () {
    final onboarding = read('lib/screens/onboarding_screen.dart');
    expect(onboarding.contains('_controller.hasClients'), isTrue);
    expect(onboarding.contains('addPostFrameCallback'), isTrue);
    expect(onboarding.contains('SingleChildScrollView'), isTrue);
  });

  test('EQ sheet scrolls and typography keeps M3 scale', () {
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('SingleChildScrollView'), isTrue);
    final theme = read('lib/theme/app_theme.dart');
    expect(theme.contains('final TextTheme swaraType = baseType;'), isTrue);
    expect(theme.contains('minimumSize: const Size'), isFalse);
  });

  test('restore and notification actions refresh live state', () {
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('_loudnessEnabled = LoudnessService.instance.enabled'), isTrue);
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('PlayerService.instance.syncUiState()'), isTrue);
  });
}
