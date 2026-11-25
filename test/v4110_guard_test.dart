import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.11 local snapshot and native reliability release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('local snapshots reuse the backup payload', () {
    final service = read('lib/services/snapshot_service.dart');
    expect(service.contains('exportLibrary()'), isTrue);
    expect(service.contains('importLibrary('), isTrue);
    expect(service.contains('getApplicationDocumentsDirectory()'), isTrue);
    expect(service.contains('maxSnapshots = 3'), isTrue);
    expect(service.contains("kLastSnapshotPrefKey = 'backup_last_snapshot_at'"), isTrue);
    expect(service.contains('minInterval'), isTrue);
    expect(service.contains('_restoreLock'), isTrue);
    final main = read('lib/main.dart');
    expect(main.contains('AppLifecycleState.paused'), isTrue);
    expect(main.contains('SnapshotService.instance.createSnapshot()'), isTrue);
    expect(main.contains('Timer.periodic('), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('.listSnapshots()'), isTrue);
    expect(settings.contains('restoreSnapshot('), isTrue);
    expect(settings.contains('markAutoRestoreOffered()'), isTrue);
  });

  test('snapshot and tag strings exist in both locales', () {
    for (final name in ['app_en.arb', 'app_id.arb']) {
      final arb = read('lib/l10n/$name');
      for (final key in [
        'dataSnapshotsSection',
        'dataSnapshotCreate',
        'dataSnapshotEmpty',
        'dataSnapshotItem',
        'dataSnapshotRestore',
        'dataSnapshotRestoreMessage',
        'dataSnapshotFailed',
        'dataSnapshotAutoTitle',
        'editMetadataWriteToFile',
        'editMetadataTagsWritten',
        'editMetadataTagsDbOnly',
      ]) {
        expect(arb.contains('"$key"'), isTrue, reason: '$name missing $key');
      }
    }
  });

  test('edited tags can be written to the OS media database', () {
    final kotlin = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraFileRename.kt',
    );
    expect(kotlin.contains('call.method == "writeTags"'), isTrue);
    expect(kotlin.contains('REQUEST_WRITE_TAGS = 4103'), isTrue);
    expect(kotlin.contains('MediaStore.Audio.Media.TITLE'), isTrue);
    final dart = read('lib/services/tag_write_service.dart');
    expect(dart.contains('const MethodChannel(channelName)'), isTrue);
    expect(dart.contains("'update_failed' => TagWriteStatus.updateFailed"), isTrue);
    final provider = read('lib/providers/library_provider.dart');
    expect(provider.contains('Future<TagWriteResult> writeTagsAndUpdate('), isTrue);
    final screen = read('lib/screens/edit_metadata_screen.dart');
    expect(screen.contains('writeTagsAndUpdate('), isTrue);
    final pub = read('pubspec.yaml');
    expect(pub.contains('taglib'), isFalse);
    expect(pub.contains('jaudiotagger'), isFalse);
  });

  test('API 29 rename uses MediaStore without createWriteRequest', () {
    final kotlin = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraFileRename.kt',
    );
    expect(kotlin.contains('Build.VERSION.SDK_INT >= 29'), isTrue);
    expect(kotlin.contains('Build.VERSION.SDK_INT == 29'), isTrue);
    expect(kotlin.contains('resolver.update(uri, values, null, null)'), isTrue);
  });

  test('dashboard invalidation covers playback and aliases are canonical', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('invalidateDashboardCache();'), isTrue);
    final normalized = read('lib/utils/backup_paths.dart');
    expect(normalized.contains('Uri.decodeFull'), isTrue);
    expect(normalized.contains("replaceAll('//', '/')"), isTrue);
    expect(db.contains('normalizeBackupPath(path)'), isTrue);
  });

  test('search isolate disposes safely', () {
    final isolate = read('lib/services/search_isolate.dart');
    expect(isolate.contains('if (_disposed) {\n      spawned.kill();'), isTrue);
  });

  test('signing secrets reject whitespace', () {
    final gradle = read('android/app/build.gradle.kts');
    expect(gradle.contains('isNullOrBlank()'), isTrue);
    for (final name in [
      '.github/workflows/build.yml',
      '.github/workflows/build-apk.yml',
    ]) {
      expect(read(name).contains('//[[:space:]]/'), isTrue);
    }
  });
}
