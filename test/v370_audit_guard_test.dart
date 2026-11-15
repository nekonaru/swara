import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v3.6.3 deep-audit fixes. The bug they pin (queue mutations
// during a crossfade landing on the wrong song, downloads being installed
// unverified) looks reasonable and is easy to reintroduce in refactors.
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
    // Native channel endpoint for the streaming digest.
    final native = read(
        'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraAudioEffects.kt');
    expect(native.contains('"sha256"'), isTrue);
    expect(native.contains('MessageDigest.getInstance("SHA-256")'), isTrue);
  });

  test('export/import keeps the listening-history triple deduped inside the transaction', () {
    final backup = read('lib/services/backup_service.dart');
    expect(
      backup.contains('database.transaction((txn) async'),
      isTrue,
      reason: 'listening history inserts must run in one transaction',
    );
  });
}
