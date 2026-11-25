import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.9 UX, signing and real file rename release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('snackbars are short and dismissible', () {
    final theme = read('lib/theme/app_theme.dart');
    expect(theme.contains('showCloseIcon: true'), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('hideCurrentSnackBar()'), isTrue);
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains(r'l10n\gen'));
    for (final file in files) {
      final text = file.readAsStringSync();
      final longSnackbar = RegExp(
        r'SnackBar\([\s\S]{0,240}?Duration\(seconds: [3-9]\d*\)',
      ).hasMatch(text);
      expect(longSnackbar, isFalse,
          reason: '${file.path} still has a long snackbar duration');
    }
  });

  test('CI signs releases with a pinned secret key', () {
    final gradle = read('android/app/build.gradle.kts');
    expect(gradle.contains('SWARA_KEYSTORE_PATH'), isTrue);
    expect(gradle.contains('create("release")'), isTrue);
    expect(gradle.contains('signingConfigs.getByName("release")'), isTrue);
    for (final name in [
      '.github/workflows/build.yml',
      '.github/workflows/build-apk.yml',
    ]) {
      final workflow = read(name);
      expect(workflow.contains('Decode release signing key'), isTrue);
      expect(workflow.contains('secrets.SWARA_KEYSTORE_B64'), isTrue);
      expect(workflow.contains('secrets.SWARA_STORE_PASSWORD'), isTrue);
    }
  });

  test('no keystore is committed', () {
    final result = Process.runSync('git', const ['ls-files']);
    final files = (result.stdout as String).split('\n').map((s) => s.toLowerCase());
    expect(files.any((f) => f.endsWith('.jks') || f.endsWith('.keystore')), isFalse);
  });

  test('real file rename bridge is wired', () {
    final plugin = File(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraFileRename.kt',
    );
    expect(plugin.existsSync(), isTrue);
    final source = plugin.readAsStringSync();
    expect(source.contains('swara/file_rename'), isTrue);
    expect(source.contains('createWriteRequest'), isTrue);
    expect(source.contains('DISPLAY_NAME'), isTrue);
    expect(source.contains('MediaScannerConnection.scanFile'), isTrue);
    final activity =
        read('android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/MainActivity.kt');
    expect(activity.contains('SwaraFileRename()'), isTrue);
    expect(activity.contains('args?.get("nextTitle")'), isTrue);
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('WRITE_EXTERNAL_STORAGE'), isTrue);
    expect(manifest.contains('maxSdkVersion="29"'), isTrue);
  });

  test('rename updates the database safely', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('Future<bool> updateSongFilePath('), isTrue);
    expect(db.contains('COLLATE NOCASE'), isTrue);
    final provider = read('lib/providers/library_provider.dart');
    expect(provider.contains('Future<FileRenameResult> renameSongFile('), isTrue);
    final options = read('lib/utils/song_options.dart');
    expect(options.contains('FileRenameService.instance.rename'), isFalse);
    expect(options.contains('lib.renameSongFile(song, displayName)'), isTrue);
    expect(options.contains('songOptionsRenameFileOnlyTitle'), isTrue);
    final player = read('lib/services/player_service.dart');
    expect(player.contains('void replaceQueueSong(Song source)'), isTrue);
  });

  test('rename and update hint strings exist in both locales', () {
    for (final name in ['app_en.arb', 'app_id.arb']) {
      final arb = read('lib/l10n/$name');
      expect(arb.contains('songOptionsRenameFileOnlyTitle'), isTrue);
      expect(arb.contains('updateSignatureOnceHint'), isTrue);
    }
  });
}
