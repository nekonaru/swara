import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.17.1 data safety release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('share import never deletes a pre-existing MediaStore row', () {
    final kt = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/'
      'SwaraAudioImport.kt',
    );
    expect(kt.contains('stalePending'), isFalse);
    expect(kt.contains('if (committed) return CopyResult(Outcome.DUPLICATE)'), isTrue);
    // No row is deleted on a failed copy; the pending row is reused later.
    expect(kt.contains('contentResolver.delete(target'), isFalse);
  });

  test('a scan never removes missing song rows', () {
    final scanner = read('lib/services/library_scanner.dart');
    expect(scanner.contains('deleteSongsMissingFromDevice('), isFalse);
    expect(scanner.contains('A scan never deletes anything'), isTrue);
    final main = read('lib/main.dart');
    expect(main.contains('pruneMetadataCache('), isFalse);
  });

  test('duplicate deletion verifies the recording', () {
    final screen = read('lib/screens/duplicates_screen.dart');
    final guards = RegExp(r'isSameRecording\(s, members\.first\)')
        .allMatches(screen)
        .length;
    expect(guards, greaterThanOrEqualTo(2));
  });
}
