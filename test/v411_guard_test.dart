import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.1.1 native/performance polish round (no new features).
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('lyrics decoding crosses the isolate as a compact map', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('static Map<int, String?> _decodeLyricsInIsolate('), isTrue);
    expect(db.contains('await compute(_decodeLyricsInIsolate, rows)'), isFalse);
    expect(db.contains('await compute(_decodeLyricsInIsolate, payload)'), isTrue);
  });

  test('EQ status listens to real DSP state changes', () {
    final service = read('lib/services/equalizer_service.dart');
    expect(service.contains('final ValueNotifier<bool> readyNotifier'), isTrue);
    expect(service.contains('void _setReady(bool value)'), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('ValueListenableBuilder<bool>'), isTrue);
  });

  test('settings only rebuilds on the fields it reads', () {
    final settings = read('lib/screens/settings_screen.dart');
    expect(
        settings.contains('context.select<LibraryProvider, '
            '(bool, bool, int, int, bool, int)>'),
        isTrue);
    expect(settings.contains('context.watch<LibraryProvider>()'), isFalse);
  });

  test('update flow retries install and cleans up the APK', () {
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('_retryInstall(path)'), isTrue);
    expect(settings.contains("case 'no_permission':"), isTrue);
    expect(settings.contains('File(path).delete()'), isTrue);
  });

  test('permission prompt waits for the intro crossfade', () {
    final main = read('lib/main.dart');
    expect(main.contains('Duration(milliseconds: 240)'), isTrue);
  });

  test('thumbnails do not fsync and controls meet 48dp', () {
    final art = read('lib/services/embedded_art_service.dart');
    expect(art.contains('writeAsBytes(bytes, flush: true)'), isFalse);
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('BoxConstraints(minHeight: 48)'), isTrue);
  });

  test('backup import errors are mapped precisely', () {
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains("e.message.contains('no entries matching')"), isTrue);
  });

  test('Indonesian backup titles are translated', () {
    final id = read('lib/l10n/app_id.arb');
    expect(id.contains('"dataSection":  "Data dan Cadangan"'), isTrue);
    expect(id.contains('"dataExport":  "Ekspor cadangan"'), isTrue);
    expect(id.contains('"dataImport":  "Impor cadangan"'), isTrue);
  });
}
