import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.18 recovery and reliability release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('boot offers recovery before the startup scan', () {
    final service = read('lib/services/recovery_service.dart');
    expect(service.contains('class RecoveryService'), isTrue);
    expect(service.contains('latestSongCount()'), isTrue);
    expect(service.contains('snapshotCount * 0.7'), isTrue);
    final home = read('lib/screens/home_screen.dart');
    expect(home.indexOf('RecoveryService.instance.shouldOffer()') <
        home.indexOf('autoLoadAndScanIfNeeded()'), isTrue);
    final snapshot = read('lib/services/snapshot_service.dart');
    expect(snapshot.contains('maxSnapshots = 5'), isTrue);
    expect(snapshot.contains('Future<int> latestSongCount()'), isTrue);
  });

  test('bulk deletion keeps an undoable safety snapshot', () {
    final screen = read('lib/screens/duplicates_screen.dart');
    expect(
      screen.contains('createSnapshot(force: true)'),
      isTrue,
    );
    expect(
      RegExp(r'label: l10n\.dataSnapshotRestore').allMatches(screen).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('repeat one skips crossfade and shuffle browse uses play order', () {
    final player = read('lib/services/player_service.dart');
    final fade = player
        .split('Future<void> _startCrossfadeToNext() async {')[1]
        .split('final playGen = _playGeneration;')[0];
    expect(fade.contains('SwaraRepeatMode.one'), isTrue);
    expect(fade.contains('_handleCompletionOnce();'), isTrue);
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('ps.songAtOrderIndex(i)?.filePath == path'), isTrue);
  });

  test('tag write resolves its row by file path', () {
    final kt = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/'
      'SwaraFileRename.kt',
    );
    expect(kt.contains('MediaStore.MediaColumns.DATA}=?'), isTrue);
  });

  test('SAF restore reads bytes and backup keeps last played', () {
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('await pickedFile.readAsBytes()'), isTrue);
    expect(settings.contains('pickedFile.length()'), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains("'lastPlayedAt': extras['lastPlayedAt']"), isTrue);
    expect(backup.contains('restoreLastPlayedAt('), isTrue);
  });
}
