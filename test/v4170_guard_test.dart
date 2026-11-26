import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.17 folder art and reliability release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('folder sidecar art is read through MediaStore, not a raw path', () {
    final service = read('lib/services/embedded_art_service.dart');
    expect(service.contains("invokeMethod<String>('folderArt'"), isTrue);
    expect(service.contains("'cover.jpg'"), isTrue);
    expect(service.contains("'folder.jpg'"), isTrue);
    expect(service.contains('_looksLikeImage(head)'), isTrue);
    expect(service.contains('source.copy('), isFalse);
    // A MediaStore exception must still allow the sidecar probe.
    final artwork = service.split('List<int>? bytes;')[1].split('if (bytes == null')[0];
    expect(artwork.contains('catch (_)'), isTrue);
    final image = read('lib/widgets/song_art_image.dart');
    expect(image.contains('filePath: widget.song.filePath'), isTrue);
  });

  test('folder art has the image permission and a native MediaStore query', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('android.permission.READ_MEDIA_IMAGES'), isTrue);
    final permission = read('lib/services/permission_service.dart');
    expect(permission.contains('Permission.photos.request()'), isTrue);
    final kotlin = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/'
      'SwaraFileRename.kt',
    );
    expect(kotlin.contains('MediaStore.Images.Media.EXTERNAL_CONTENT_URI'), isTrue);
    expect(kotlin.contains('canReadImages'), isTrue);
  });

  test('voice title and artist search excludes folders inside SQL', () {
    final db = read('lib/services/db_helper.dart');
    final query = db.split('Future<List<Song>> querySongsByTitleAndArtist(')[1]
        .split('Future<List<Song>> querySongsPage(')[0];
    expect(query.contains('Set<String>? excludedFolders'), isTrue);
    expect(query.contains("filePath NOT LIKE ? ESCAPE '\\\\'"), isTrue);
    final catalog = read('lib/services/swara_browse_catalog.dart');
    expect(catalog.contains('excludedFolders: excluded'), isTrue);
    expect(catalog.contains('isHiddenPath(song.filePath, excluded)'), isFalse);
  });

  test('stale widget rows fall back to the file path', () {
    final main = read('lib/main.dart');
    expect(main.contains('Slot ids are index based and change after removals'), isTrue);
    expect(main.contains('service.songAtOrderIndex(i)?.filePath == path'), isTrue);
  });

  test('play-stat rebuild has an in-flight guard', () {
    final service = read('lib/services/smart_playlist_service.dart');
    expect(service.contains('_playStatsRebuildInFlight'), isTrue);
    expect(service.contains('if (_playStatsRebuildInFlight) return;'), isTrue);
    expect(service.contains('finally {'), isTrue);
  });
}
