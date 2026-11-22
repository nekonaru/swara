import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('Android Auto media descriptor is declared', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('com.google.android.gms.car.application'), isTrue);
    expect(manifest.contains('@xml/automotive_app_desc'), isTrue);
    final descriptor = read('android/app/src/main/res/xml/automotive_app_desc.xml');
    expect(descriptor.contains('<uses name="media" />'), isTrue);
  });

  test('notification custom actions are wired', () {
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('ic_notif_sleep'), isTrue);
    expect(handler.contains('ic_notif_favorite'), isTrue);
    expect(handler.contains("name: 'sleep15'"), isTrue);
    expect(handler.contains("name: 'favorite'"), isTrue);
    expect(handler.contains('setSleepTimer(const Duration(minutes: 15))'), isTrue);
    final keep = read('android/app/src/main/res/raw/keep.xml');
    expect(keep.contains('ic_notif_sleep'), isTrue);
    expect(keep.contains('ic_notif_favorite'), isTrue);
    for (final f in ['app_en.arb', 'app_id.arb']) {
      expect(read('lib/l10n/$f').contains('notificationSleep15'), isTrue);
    }
  });

  test('named EQ gains survive restart and restore', () {
    final theme = read('lib/providers/theme_provider.dart');
    expect(theme.contains('activeEqGains = const <double>[]'), isTrue);
    final main = read('lib/main.dart');
    expect(main.contains('themeProvider.gainsForActivePreset()'), isTrue);
  });

  test('aborted crossfade and resume restore player volume', () {
    final player = read('lib/services/player_service.dart');
    expect(player.contains('unawaited(_vol(() => _setVol(_activePlayer, 1)))'), isTrue);
    expect(player.contains('await refreshPlaybackSettings();'), isTrue);
    expect(player.contains('_trimByPlayer.clear();'), isTrue);
  });

  test('cancel is not reported as a download failure', () {
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('lastDownloadCancelled'), isTrue);
  });
}
