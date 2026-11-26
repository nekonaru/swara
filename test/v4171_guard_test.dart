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
    expect(kt.contains('val found = existing?.use'), isTrue);
    expect(kt.contains('if (found) return CopyResult(Outcome.DUPLICATE)'), isTrue);
    // Only the row this import just created may be removed on a copy failure.
    expect(kt.contains('delete(target, null, null)'), isTrue);
  });

  test('ghost cleanup requires a nearly complete device result', () {
    final scanner = read('lib/services/library_scanner.dart');
    expect(scanner.contains('(dbCount * 0.95).ceil()'), isTrue);
    expect(scanner.contains('(dbCount * 0.02).ceil().clamp(1, 20)'), isTrue);
    expect(scanner.contains('ghostCount > 0 && ghostCount <= maxGhosts'), isTrue);
  });

  test('duplicate deletion verifies the recording', () {
    final screen = read('lib/screens/duplicates_screen.dart');
    final guards = RegExp(r'isSameRecording\(s, members\.first\)')
        .allMatches(screen)
        .length;
    expect(guards, greaterThanOrEqualTo(2));
  });
}
