import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v3.12.2 design/logic polish pass: no new features, only
// theme-consistent visuals and existing-feature anomaly fixes.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  List<String> dartFiles(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path.replaceAll('\\', '/'))
      .toList();

  group('design tokens', () {
    test('error and inactive colors come from the theme', () {
      final offenders = <String>[];
      for (final file in [...dartFiles('lib/screens'), ...dartFiles('lib/widgets')]) {
        final text = File(file).readAsStringSync();
        if (text.contains('Colors.red') || text.contains('Colors.grey')) {
          offenders.add(file);
        }
      }
      expect(offenders, isEmpty, reason: 'hard-coded colors in: $offenders');
    });

    test('bottom sheets inherit the shared 24dp shape', () {
      final offenders = <String>[];
      for (final file in dartFiles('lib/screens')) {
        final text = File(file).readAsStringSync();
        if (text.contains('Radius.vertical(top: Radius.circular(20))')) {
          offenders.add(file);
        }
      }
      expect(offenders, isEmpty, reason: 'sheet shape overrides in: $offenders');
    });

    test('system bars follow the active theme', () {
      final main = read('lib/main.dart');
      expect(main.contains('AnnotatedRegion<SystemUiOverlayStyle>'), isTrue);
      expect(main.contains('systemNavigationBarColor: scheme.surface'), isTrue);
    });

    test('accent check adapts to swatch luminance', () {
      final settings = read('lib/screens/settings_screen.dart');
      expect(settings.contains('computeLuminance()'), isTrue);
    });
  });

  group('existing-feature anomalies', () {
    test('playlist reorder replaces the source list', () {
      final source = read('lib/screens/playlist_detail_screen.dart');
      expect(source.contains('_songs = reordered;'), isTrue);
      expect(source.contains('_songs.removeAt(oldIndex)'), isFalse);
    });

    test('bulk edit counts a successful write before the reload', () {
      final source = read('lib/screens/bulk_edit_screen.dart');
      final write = source.indexOf('updateSongMetadataBulk(updates)');
      final ok = source.indexOf('ok = updates.length');
      expect(write >= 0 && ok > write, isTrue);
    });

    test('clipboard operations are guarded', () {
      final settings = read('lib/screens/settings_screen.dart');
      expect(
        RegExp(r'try\s*\{\s*await Clipboard\.setData').hasMatch(settings),
        isTrue,
      );
      expect(
        RegExp(r'try\s*\{\s*final data = await Clipboard\.getData')
            .hasMatch(settings),
        isTrue,
      );
    });

    test('overflow buttons are labelled', () {
      for (final file in [
        'lib/screens/history_screen.dart',
        'lib/screens/library_screen.dart',
        'lib/screens/search_screen.dart',
        'lib/screens/extra_screens.dart',
        'lib/screens/playlist_detail_screen.dart',
        'lib/screens/collections_screen.dart',
      ]) {
        expect(File(file).readAsStringSync().contains('moreOptions'), isTrue,
            reason: '$file has an unlabeled overflow button');
      }
    });
  });

  group('motion settles smoothly', () {
    test('paused indicator animates to rest', () {
      final source = read('lib/widgets/playing_indicator.dart');
      expect(source.contains('c.animateTo(0.0'), isTrue);
    });

    test('dismiss and queue scroll ease instead of snapping', () {
      final player = read('lib/screens/player_screen.dart');
      expect(player.contains('_returnController.forward(from: 0)'), isTrue);
      final queue = read('lib/screens/queue_screen.dart');
      expect(queue.contains('_scrollController.animateTo('), isTrue);
      expect(queue.contains('_scrollController.jumpTo('), isFalse);
    });
  });
}
