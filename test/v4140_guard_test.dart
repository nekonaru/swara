import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.14 shared audio import release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('app accepts audio shared from other apps', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('android.intent.action.SEND_MULTIPLE'), isTrue);
    expect(manifest.contains('android.intent.action.VIEW'), isTrue);
    expect(manifest.contains('android:mimeType="audio/*"'), isTrue);
    final activity = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/MainActivity.kt',
    );
    expect(activity.contains('clipData'), isTrue);
    expect(activity.contains('pendingImportUris'), isTrue);
    expect(activity.contains('getInitialImport'), isTrue);
    expect(activity.contains('onImportUris'), isTrue);
    expect(activity.contains('takePersistableUriPermission'), isTrue);
    final native = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraAudioImport.kt',
    );
    expect(native.contains('IS_PENDING'), isTrue);
    expect(native.contains('RELATIVE_PATH'), isTrue);
    expect(native.contains('MediaScannerConnection.scanFile'), isTrue);
    expect(native.contains('openInputStream'), isTrue);
    expect(native.contains('openOutputStream'), isTrue);
  });

  test('Dart side imports and rescans', () {
    final service = read('lib/services/share_import_service.dart');
    expect(service.contains("MethodChannel('swara/share_import')"), isTrue);
    expect(service.contains('getInitialImport'), isTrue);
    expect(service.contains('importUris'), isTrue);
    final main = read('lib/main.dart');
    expect(main.contains('onImportUris'), isTrue);
    expect(main.contains('scanDevice()'), isTrue);
    final provider = read('lib/providers/library_provider.dart');
    expect(provider.contains('static final LibraryProvider instance'), isTrue);
  });

  test('share import strings exist in both locales', () {
    for (final name in ['app_en.arb', 'app_id.arb']) {
      final arb = read('lib/l10n/$name');
      for (final key in [
        'shareImportImported',
        'shareImportSkipped',
        'shareImportFailed',
      ]) {
        expect(arb.contains('"$key"'), isTrue, reason: '$name missing $key');
      }
    }
  });
}
