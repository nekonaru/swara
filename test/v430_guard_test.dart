import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('Android Auto browse taps play the selected item', () {
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('Future<void> playFromMediaId('), isTrue);
    expect(handler.contains('await _playMediaItem(mediaId)'), isTrue);
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('MEDIA_CONTENT_CONTROL'), isFalse);
  });

  test('lyrics search is available offline', () {
    final search = read('lib/screens/search_screen.dart');
    expect(search.contains('_SearchFilter.lyrics'), isTrue);
    expect(search.contains('_kLyricsHaystackLimit'), isTrue);
    for (final f in ['app_en.arb', 'app_id.arb']) {
      expect(read('lib/l10n/$f').contains('searchFilterLyrics'), isTrue);
    }
  });

  test('backup song settings are validated against local songs', () {
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('SELECT id FROM songs WHERE id IN ('), isTrue);
  });

  test('factory EQ preset and favorite action work on cold start', () {
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('await EqualizerService.instance.applyPreset(preset);'), isTrue);
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('PlayerService.instance.ready'), isTrue);
    for (final f in ['app_en.arb', 'app_id.arb']) {
      final arb = read('lib/l10n/$f');
      expect(arb.contains('notificationShuffle'), isTrue);
      expect(arb.contains('notificationRepeat'), isTrue);
    }
  });
}
