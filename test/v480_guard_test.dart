import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.8 native surface and performance release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('Android Auto has a real offline browse tree', () {
    final catalog = read('lib/services/swara_browse_catalog.dart');
    for (final id in [
      'cat_playlists',
      'cat_folders',
      'cat_songs',
      'cat_queue',
    ]) {
      expect(catalog.contains("'$id'"), isTrue, reason: 'missing $id');
    }
    expect(catalog.contains('playable: false'), isTrue);
    expect(catalog.contains('queue_-1_'), isTrue);
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('Future<List<MediaItem>> getChildren('), isTrue);
    expect(handler.contains('Future<List<MediaItem>> search('), isTrue);
    expect(handler.contains('getSongByFilePath(path)'), isTrue);
    expect(handler.contains('lookupAppLocalizations(LanguageProvider.instance.locale).queueTitle'), isTrue);
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('getSongByFilePath(String filePath)'), isTrue);
    final descriptor =
        read('android/app/src/main/res/xml/automotive_app_desc.xml');
    expect(descriptor.contains('<uses name="media" />'), isTrue);
  });

  test('widget shows the next queued title', () {
    final service = read('lib/services/player_service.dart');
    expect(service.contains('String? get nextTitle'), isTrue);
    final main = read('lib/main.dart');
    expect(main.contains("'nextTitle': nextTitle"), isTrue);
    expect(main.contains('nextTitle != lastNextTitle'), isTrue);
    final activity =
        read('android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/MainActivity.kt');
    expect(activity.contains('args?.get("nextTitle")'), isTrue);
    final provider =
        read('android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraWidgetProvider.kt');
    expect(provider.contains('KEY_NEXT_TITLE'), isTrue);
    expect(provider.contains('R.id.widget_next_line'), isTrue);
    expect(provider.contains('View.GONE'), isTrue);
    final layout = read('android/app/src/main/res/layout/swara_widget.xml');
    expect(layout.contains('@+id/widget_next_line'), isTrue);
    for (final name in ['values/strings.xml', 'values-id/strings.xml']) {
      expect(read('android/app/src/main/res/$name')
          .contains('widget_next_label'), isTrue);
    }
  });

  test('playlist replacement keeps order and is transactional', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('replacePlaylistSongs('), isTrue);
    expect(db.contains("'position': position++"), isTrue);
    expect(db.contains('if (!seen.add(id)) continue;'), isTrue);
  });

  test('offset writes are serialized', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('Future<void> _offsetWrite'), isTrue);
    expect(player.contains('Future<void> _writeLrcOffset('), isTrue);
    expect(player.contains('await _offsetWrite;'), isTrue);
  });

  test('decoded cover paths are remembered without blocking the UI', () {
    final art = read('lib/widgets/song_art_image.dart');
    expect(art.contains('noteValidCover('), isTrue);
    expect(art.contains('_validCoverPaths'), isTrue);
    expect(art.contains('frameBuilder:'), isTrue);
    expect(art.contains('existsSync()'), isFalse);
  });

  test('backup only marks restored tags as scanned', () {
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('metadataScanned: raw[\'metadataScanned\'] == true &&'), isTrue);
  });
}
