import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v3.12.0 deep audit: data-loss fixes, player/session
// consistency and the new DSP/backup/smart-playlist features. These bugs are
// easy to reintroduce during refactors, so they are pinned with source checks.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  group('scanner preserves library data', () {
    final scanner = read('lib/services/library_scanner.dart');

    test('repathed ghost ids survive the delete pass', () {
      expect(scanner.contains('keepIds = {...allDeviceIds, ...reused}'), isTrue,
          reason: 'a moved file keeps its old row id and must not be deleted');
      expect(scanner.contains('return reused;'), isTrue);
    });

    test('a MediaStore re-id becomes an update instead of REPLACE', () {
      expect(scanner.contains('_reusePathCollidingRows'), isTrue);
      expect(scanner.contains("'filePath': path,"), isTrue);
      // Unchunked IN lists break on Android 8/9 SQLite (999 variables).
      expect(scanner.contains('const chunk = 400;'), isTrue);
    });

    test('database v12 marks auto playlists explicitly', () {
      final db = read('lib/services/db_helper.dart');
      expect(db.contains('version: 13'), isTrue);
      expect(db.contains('ALTER TABLE playlists ADD COLUMN isAuto'), isTrue);
      expect(db.contains('getForgottenFavorites'), isTrue);
    });
  });

  group('playback stays in sync', () {
    final player = read('lib/services/player_service.dart');

    test('sleep stop and crossfade cannot own the same players', () {
      final sleepFade = player.split('Future<void> _startSleepFadeOut()')[1];
      expect(sleepFade.contains('_abortCrossfadeForQueueEdit()'), isTrue);
      final pauseForSleep = player.split('void _pauseBothForSleep()')[1];
      expect(pauseForSleep.contains('_abortCrossfadeForQueueEdit()'), isTrue);
      expect(pauseForSleep.contains('_clearABRepeatSilent()'), isTrue);
    });

    test('session state follows queue and player changes', () {
      expect(player.contains('queueVersion++;\n      notifyListeners();'), isTrue);
      expect(player.contains('AudioPlayer get activePlayer'), isTrue);
      expect(player.contains('_playbackFlipCount++'), isTrue);
      expect(player.contains('unawaited(_skipUnplayableAndContinue());'), isTrue);
      expect(player.contains('_resumeSaveTimer?.cancel();'), isTrue);
    });

    test('media session advertises transport actions', () {
      final handler = read('lib/services/swara_audio_handler.dart');
      for (final action in [
        'MediaAction.play',
        'MediaAction.pause',
        'MediaAction.stop',
      ]) {
        expect(handler.contains(action), isTrue, reason: '$action missing');
      }
      expect(handler.contains('AudioProcessingState.idle'), isTrue);
    });
  });

  group('v3.12.0 features are wired', () {
    test('loudness normalization runs on the native DSP', () {
      final native = read(
          'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraAudioEffects.kt');
      expect(native.contains('LoudnessEnhancer'), isTrue);
      expect(native.contains('"attachLoudness"'), isTrue);
      expect(native.contains('setTargetGain(600)'), isTrue);
      final service = read('lib/services/loudness_service.dart');
      expect(service.contains('prefsKey'), isTrue);
      expect(service.contains('attachLoudness'), isTrue);
      final settings = read('lib/screens/settings_screen.dart');
      expect(settings.contains('loudnessNormalization'), isTrue);
    });

    test('backup can be saved to a file and last export is shown', () {
      final backup = read('lib/services/backup_service.dart');
      expect(backup.contains('saveBackupToFile'), isTrue);
      expect(backup.contains('kLastExportPrefKey'), isTrue);
      expect(backup.contains('Unsupported backup version'), isTrue);
      expect(backup.contains('dashboard_aggregate_cache_v1'), isTrue);
      final settings = read('lib/screens/settings_screen.dart');
      expect(settings.contains('dataSaveToFile'), isTrue);
      expect(settings.contains('dataLastExport'), isTrue);
    });

    test('forgotten favorites joins the auto playlists', () {
      final collections = read('lib/screens/collections_screen.dart');
      expect(collections.contains('_forgottenName'), isTrue);
      expect(collections.contains('_syncForgottenFavorites'), isTrue);
      expect(collections.contains('isAuto: true'), isTrue);
    });

    test('native platform settings match the documented minimum OS', () {
      final gradle = read('android/app/build.gradle.kts');
      expect(gradle.contains('minSdk = 26'), isTrue);
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      // Android Auto and Wear must be able to bind to the media service.
      expect(manifest.contains('android.permission.MEDIA_CONTENT_CONTROL'), isFalse);
    });
  });
}
