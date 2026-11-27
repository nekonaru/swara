import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v5.1 design, motion and accessibility release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('motion vocabulary is shared and honours reduced motion', () {
    final motion = read('lib/utils/motion.dart');
    expect(motion.contains('abstract final class SwaraMotion'), isTrue);
    expect(motion.contains('static const Duration feedback'), isTrue);
    expect(motion.contains('static const Duration small'), isTrue);
    expect(motion.contains('static const Duration page'), isTrue);
    expect(motion.contains('reduceMotion(context)'), isTrue);
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('SwaraMotion.of(context'), isTrue);
    final mini = read('lib/widgets/mini_player.dart');
    expect(mini.contains('SwaraMotion.of('), isTrue);
  });

  test('design tokens exist and are used', () {
    final theme = read('lib/theme/app_theme.dart');
    expect(theme.contains('abstract final class SwaraSpace'), isTrue);
    expect(theme.contains('abstract final class SwaraRadius'), isTrue);
    final empty = read('lib/widgets/swara_empty_state.dart');
    expect(empty.contains('SwaraSpace.lg'), isTrue);
    expect(empty.contains('Semantics('), isTrue);
  });

  test('empty states are shared instead of bare text', () {
    final extras = read('lib/screens/v5_extras_screen.dart');
    expect(extras.contains('SwaraEmptyState('), isTrue);
    expect(extras.contains("title: 'Nothing in trash'"), isFalse);
  });

  test('cover hero keeps one shared tag', () {
    final mini = read('lib/widgets/mini_player.dart');
    final player = read('lib/screens/player_screen.dart');
    const tag = r"tag: 'swara_art_${song.id}'";
    expect(tag.allMatches(mini).length, 1);
    expect(tag.allMatches(player).length, 1);
  });

  test('predictive back is enabled natively', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(
        manifest.contains('android:enableOnBackInvokedCallback="true"'), isTrue);
  });
}
