import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.10 performance and reliability release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('search uses one persistent isolate', () {
    final screen = read('lib/screens/search_screen.dart');
    expect(screen.contains('_searchIsolate.prepare('), isTrue);
    expect(screen.contains('_searchIsolate.search('), isTrue);
    expect(screen.contains('_searchIsolate.dispose()'), isTrue);
    expect(screen.contains('compute(filterSongsIsolate'), isFalse);
    final support = read('lib/services/search_isolate.dart');
    expect(support.contains('Isolate.spawn(searchIsolateEntry'), isTrue);
    expect(support.contains("case 'prepare'"), isTrue);
    expect(support.contains('_latestIssued'), isTrue);
  });

  test('dashboard caches all detail lists with an epoch', () {
    final screen = read('lib/screens/dashboard_screen.dart');
    expect(screen.contains('_readDashboardCache()'), isTrue);
    expect(screen.contains('_writeDashboardCache('), isTrue);
    expect(screen.contains('_epochKey'), isTrue);
    expect(screen.contains('map[\'epoch\'] != (prefs.getInt(_epochKey) ?? 0)'), isTrue);
    expect(screen.contains('return;'), isTrue);
    expect(screen.contains('getExcludedFolders()'), isTrue);
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('dashboardCacheEpochKey'), isTrue);
    expect(db.contains('static Future<void> invalidateDashboardCache()'), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('DBHelper.invalidateDashboardCache()'), isTrue);
    final library = read('lib/providers/library_provider.dart');
    expect(library.contains('unawaited(DBHelper.invalidateDashboardCache())'), isTrue);
  });

  test('backup v15 remembers old paths after a real rename', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('version: 17'), isTrue);
    expect(db.contains('CREATE TABLE song_path_aliases'), isTrue);
    expect(db.contains("'path': oldPath"), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('identityAliases'), isTrue);
    expect(backup.contains("raw['aliases']"), isTrue);
  });

  test('rename handles API 29 without calling an API 30 method', () {
    final kotlin = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraFileRename.kt',
    );
    expect(kotlin.contains('Build.VERSION.SDK_INT >= 29'), isTrue);
    expect(kotlin.contains('Build.VERSION.SDK_INT == 29'), isTrue);
    expect(kotlin.contains('getSdkInt'), isTrue);
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('requestLegacyExternalStorage="true"'), isTrue);
    final service = read('lib/services/file_rename_service.dart');
    expect(service.contains('sdk <= 29'), isTrue);
  });

  test('CI refuses incomplete signing secrets', () {
    final gradle = read('android/app/build.gradle.kts');
    expect(gradle.contains('signingVars.any'), isTrue);
    expect(gradle.contains('Refusing to fall back to the debug key'), isTrue);
    for (final name in [
      '.github/workflows/build.yml',
      '.github/workflows/build-apk.yml',
    ]) {
      final workflow = read(name);
      expect(workflow.contains('SWARA_KEY_ALIAS'), isTrue);
      expect(workflow.contains('test -n'), isTrue);
    }
  });

  test('all snackbars replace the previous message', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains(r'l10n\gen'))
        .where((f) => !f.path.endsWith('settings_screen.dart'));
    for (final file in files) {
      final text = file.readAsStringSync();
      final direct = RegExp(r'ScaffoldMessenger\.of\([^)]+\)\s*\.showSnackBar\(')
          .hasMatch(text);
      expect(direct, isFalse, reason: '${file.path} stacks snackbars');
    }
    final options = read('lib/utils/song_options.dart');
    expect(options.contains('songOptionsRenameRepairFailed'), isTrue);
  });
}
