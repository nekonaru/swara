import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.17 folder art and reliability release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('folder sidecar art is used when there is no embedded tag', () {
    final service = read('lib/services/embedded_art_service.dart');
    expect(service.contains('Future<String?> _folderArt('), isTrue);
    expect(service.contains("'cover.jpg'"), isTrue);
    expect(service.contains("'folder.jpg'"), isTrue);
    expect(service.contains('source.copy(cacheFile.path)'), isTrue);
    final image = read('lib/widgets/song_art_image.dart');
    expect(image.contains('filePath: widget.song.filePath'), isTrue);
  });

  test('voice title and artist search hides excluded folders', () {
    final catalog = read('lib/services/swara_browse_catalog.dart');
    expect(catalog.contains('isHiddenPath(song.filePath, excluded)'), isTrue);
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
