import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guard: the README feature tables stay in sync with the shipped features.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('README documents named EQ presets', () {
    final readme = read('README.md');
    final id = read('README.id.md');
    expect(readme.contains('Named EQ presets') || readme.contains('EQ presets'), isTrue);
    expect(id.contains('preset EQ') || id.contains('Preset EQ'), isTrue);
  });
}
