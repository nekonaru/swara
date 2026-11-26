import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.20 native smoothness release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('widget rebuilds once and reuses its decoded cover', () {
    final kt = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/'
      'SwaraWidgetProvider.kt',
    );
    final update = kt
        .split('fun updateAll(')[1]
        .split('private fun playSlotTemplate(')[0];
    expect(update.contains('val views = buildViews(context)'), isTrue);
    expect(update.contains('if (queueChanged)'), isTrue);
    expect(update.contains('lastQueueJson'), isTrue);
    expect(kt.contains('cachedArtPath'), isTrue);
    expect(kt.contains('artPath == cachedArtPath'), isTrue);
  });

  test('cover paths never stat on the UI isolate', () {
    final art = read('lib/widgets/song_art_image.dart');
    expect(art.contains('existsSync()'), isFalse);
    expect(art.contains('_maxValidPaths = 4096'), isTrue);
    expect(art.contains('static void clearCoverCache()'), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('SongArtImage.clearCoverCache()'), isTrue);
  });

  test('widget payload and media session are fingerprinted', () {
    final main = read('lib/main.dart');
    expect(main.contains('String _widgetQueueJson('), isTrue);
    final push = main.split('Future<void> push({bool force = false})')[1]
        .split('// Republish the widget')[0];
    expect(push.indexOf('final fingerprint') < push.indexOf('_widgetQueueJson('),
        isTrue);
    expect(main.contains('final looping = service.hasABRepeat'), isTrue);
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('_lastNotifyFingerprint'), isTrue);
    expect(handler.contains('notifyFingerprint == _lastNotifyFingerprint'), isTrue);
  });

  test('first fling skips repeated folder art probes', () {
    final service = read('lib/services/embedded_art_service.dart');
    expect(service.contains('_noSidecarFolders'), isTrue);
    expect(service.contains('_noSidecarFolders.add(folder)'), isTrue);
  });

  test('play all does not notify twice', () {
    final player = read('lib/services/player_service.dart');
    final block = player
        .split('// Early notify gives immediate mini-player feedback;')[1]
        .split('List<int> _buildShuffledOrder')[0];
    expect(RegExp(r'notifyListeners\(\)').allMatches(block).length, 1);
  });

  test('recovery question waits until the library is loaded', () {
    final home = read('lib/screens/home_screen.dart');
    final init = home.split('Future<void> _initLibrary()')[1]
        .split('// No metadata scan is started')[0];
    expect(init.indexOf('await lib.loadFromDb()') <
        init.indexOf('RecoveryService.instance.shouldOffer()'), isTrue);
  });
}
