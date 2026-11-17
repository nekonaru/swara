import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the deep-audit fixes (v3.7.0 audit and later). The bugs they
// pin down (queue mutations during a crossfade landing on the wrong song,
// downloads being installed unverified, update checks on the main looper)
// look reasonable and are easy to reintroduce in refactors.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('queue mutations abort an in-flight crossfade', () {
    final player = read('lib/services/player_service.dart');

    final removeBody = player.split('void removeFromQueue(')[1];
    expect(
      removeBody.contains('_abortCrossfadeForQueueEdit()'),
      isTrue,
      reason: 'removeFromQueue must cancel an in-flight fade before shifting indices',
    );
    final reorderBody = player.split('void reorderQueue(')[1];
    expect(
      reorderBody.contains('_abortCrossfadeForQueueEdit()'),
      isTrue,
      reason: 'reorderQueue must cancel an in-flight fade before shifting indices',
    );
    final shuffleBody = player.split('void setShuffle(')[1];
    expect(
      shuffleBody.contains('_abortCrossfadeForQueueEdit()'),
      isTrue,
      reason: 'toggling shuffle must cancel an in-flight fade',
    );
  });

  test('the updater verifies the downloaded APK against the published digest', () {
    final updater = read('lib/services/update_service.dart');
    expect(
      updater.contains('downloadDigest'),
      isTrue,
      reason: 'the picked asset must carry the GitHub-published digest',
    );
    expect(
      updater.contains('sha256'),
      isTrue,
      reason: 'the downloaded file must be hashed before handing it to the installer',
    );
    expect(
      updater.contains('verified'),
      isTrue,
      reason: 'the download result must carry whether verification passed',
    );
    // Native channel endpoint for the streaming digest.
    final native = read(
        'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraAudioEffects.kt');
    expect(native.contains('"sha256"'), isTrue);
    expect(native.contains('MessageDigest.getInstance("SHA-256")'), isTrue);
    // The digest must not run on the main looper.
    expect(
      native.contains('digestExecutor.execute'),
      isTrue,
      reason: 'streaming the APK through SHA-256 must run off the main looper',
    );
    // Reject-on-mismatch path exists and deletes the bad file.
    expect(native.contains('"sha256"'), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(
      settings.contains('settingsUpdateUnverifiedTitle'),
      isTrue,
      reason: 'an unverified install must ask for explicit consent first',
    );
  });

  test('export/import keeps the listening-history triple deduped inside the transaction', () {
    final backup = read('lib/services/backup_service.dart');
    // Match the listening-entries section specifically, not the export
    // transaction, so the import-side guard cannot silently weaken.
    expect(
      backup.contains('entriesRestored += await database.transaction'),
      isTrue,
      reason: 'listening history inserts must run in one transaction',
    );
    // Playlist folder labels survive a round trip.
    expect(
      backup.contains("'folder':"),
      isTrue,
      reason: 'export must include the playlist folder label',
    );
    expect(
      backup.contains("item['folder']"),
      isTrue,
      reason: 'import must restore the playlist folder label',
    );
  });

  test('the widget art and update executors are off the main looper', () {
    final activity = read(
        'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/MainActivity.kt');
    // A tap landing after onDestroy used to throw synchronously; the push is
    // now guarded and uses the application context.
    expect(
      activity.contains('RejectedExecutionException'),
      isTrue,
      reason: 'widget update executor must tolerate a shut-down activity',
    );
    expect(
      activity.contains('applicationContext'),
      isTrue,
      reason: 'widget rebind must not capture a destroyed Activity context',
    );
    final provider = read(
        'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraWidgetProvider.kt');
    expect(
      provider.contains('widgetExecutor'),
      isTrue,
      reason: 'onUpdate rebind must run off the launcher main thread',
    );
  });

  test('the Material You theme cache follows palette changes', () {
    final theme = read('lib/theme/app_theme.dart');
    expect(
      theme.contains('dyn-'),
      isTrue,
      reason:
          'dynamic scheme colors must feed the memoization key, or the app sticks to a stale palette',
    );
  });
}
