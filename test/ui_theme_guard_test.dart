import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guards for the central theme and the mini player to player
/// artwork flight.
///
/// Every visual default used to be decided per screen, so the app bar in one
/// place disagreed with the app bar in the next, muted subtitles came in three
/// different greys, and opening the player swapped two unrelated pictures
/// instead of growing the small cover. These guards pin the structure that
/// keeps that from coming back: both themes must come from one builder, the
/// builder must actually define the shared component styles, and the two ends
/// of the artwork flight must keep the same tag.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  group('central theme', () {
    test('light and dark both come from the shared builder', () {
      final main = read('lib/main.dart');
      expect(
        main.contains('buildSwaraTheme('),
        isTrue,
        reason: 'the light theme must be built by buildSwaraTheme, not by a '
            'bare ThemeData(...) that only sets a colour seed',
      );
      expect(
        main.contains('colorSchemeSeed'),
        isFalse,
        reason: 'a raw colorSchemeSeed in main would bypass every component '
            'default defined in app_theme.dart',
      );

      final provider = read('lib/providers/theme_provider.dart');
      expect(
        provider.contains('buildSwaraTheme('),
        isTrue,
        reason: 'the dark theme must come from the same builder, otherwise '
            'light and dark drift apart on card, dialog and app bar styles',
      );
    });

    test('the builder defines the shared component styles', () {
      final theme = read('lib/theme/app_theme.dart');
      // Each of these is what stopped screens from hand rolling their own
      // version of the same widget.
      const required = <String, String>{
        'appBarTheme': 'flat, same app bar on every screen',
        'cardTheme': 'one card radius and tone',
        'dialogTheme': 'one dialog shape and text style',
        'listTileTheme': 'one row shape, so press ripples match',
        'filledButtonTheme': 'one button shape and padding',
        'snackBarTheme': 'floating snackbars by default',
        'tabBarTheme': 'library tabs styled with the scheme colours',
        'pageTransitionsTheme': 'one page transition for the whole app',
      };
      required.forEach((key, why) {
        expect(
          theme.contains(key),
          isTrue,
          reason: 'buildSwaraTheme must set $key, otherwise $why',
        );
      });
    });

    test('the AMOLED option keeps a black surface', () {
      final theme = read('lib/theme/app_theme.dart');
      expect(
        theme.contains('amoledBlack'),
        isTrue,
        reason: 'the builder must accept the AMOLED flag, which main and the '
            'theme provider both rely on for a pitch black background',
      );
      expect(
        theme.contains('scaffoldBackgroundColor'),
        isTrue,
        reason: 'the black surface has to reach scaffoldBackgroundColor, not '
            'only the colour scheme, or the background stays grey',
      );
    });
  });

  group('artwork flight', () {
    test('both ends of the flight share one tag', () {
      final mini = read('lib/widgets/mini_player.dart');
      final player = read('lib/screens/player_screen.dart');

      expect(
        mini.contains("tag: 'swara_art_\${song.id}'"),
        isTrue,
        reason: 'the mini player cover must carry the flight tag',
      );
      expect(
        player.contains("tag: 'swara_art_\${song.id}'"),
        isTrue,
        reason: 'the player cover must carry the same tag, otherwise opening '
            'the player shows a plain swap instead of the artwork flying up',
      );
      expect(
        mini.contains('Hero('),
        isTrue,
        reason: 'the tag is useless without the Hero widget wrapping it',
      );
      expect(
        player.contains('Hero('),
        isTrue,
        reason: 'the tag is useless without the Hero widget wrapping it',
      );
    });

    test('the player keeps its own slide up route', () {
      final transitions = read('lib/utils/page_transitions.dart');
      expect(
        transitions.contains('SlideUpRoute'),
        isTrue,
        reason: 'the player opens as a bottom sheet style page, which is a '
            'different motion from the shared page transition',
      );
    });
  });
}
