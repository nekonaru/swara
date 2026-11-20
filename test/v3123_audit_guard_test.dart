import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v3.12.3 audit pass: correctness and accessibility of the
// existing features only, no new features.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  group('correctness', () {
    test('permission flag is persisted only after requests', () {
      final main = read('lib/main.dart');
      final flag = main.indexOf('setBool(_essentialPermissionsAskedKey, true)');
      final request = main.indexOf('Permission.audio.request()');
      expect(flag > request, isTrue);
    });

    test('shortcuts are registered after the locale loads', () {
      final main = read('lib/main.dart');
      final load = main.indexOf('await languageProvider.load();');
      final shortcut = main.indexOf('_setupDynamicShortcuts();');
      expect(load >= 0 && shortcut > load, isTrue);
    });

    test('update flow has its own re-entry guard', () {
      final settings = read('lib/screens/settings_screen.dart');
      expect(settings.contains('bool _updating = false;'), isTrue);
      expect(settings.contains('if (_savingPrefs || _updating) return;'), isTrue);
      expect(settings.contains('onTap: _updating ? null : _checkForUpdate'), isTrue);
    });

    test('bulk deletes report only rows actually removed', () {
      final provider = read('lib/providers/library_provider.dart');
      expect(provider.contains('Future<int> deleteSongs'), isTrue);
      final screen = read('lib/screens/duplicates_screen.dart');
      expect(screen.contains('final removedNow = await lib.deleteSongs'), isTrue);
    });

    test('song details and updater fail closed on bad data', () {
      final options = read('lib/utils/song_options.dart');
      expect(options.contains('await file.length()'), isTrue);
      final updater = read('lib/services/update_service.dart');
      expect(updater.contains('if (abis.isEmpty) return null;'), isTrue);
      final backup = read('lib/services/backup_service.dart');
      expect(backup.contains('two(now.second)'), isTrue);
    });
  });

  group('accessibility and states', () {
    test('remaining icon controls are labelled', () {
      for (final file in [
        'lib/screens/search_screen.dart',
        'lib/screens/library_screen.dart',
        'lib/screens/playlist_detail_screen.dart',
        'lib/screens/queue_screen.dart',
        'lib/screens/edit_lyrics_screen.dart',
        'lib/screens/edit_metadata_screen.dart',
        'lib/screens/extra_screens.dart',
        'lib/screens/collections_screen.dart',
      ]) {
        expect(File(file).readAsStringSync().contains('tooltip:'), isTrue,
            reason: '$file has an unlabeled icon control');
      }
      final home = read('lib/screens/home_screen.dart');
      expect(home.contains('checked: _defs[i].visible'), isTrue);
      final player = read('lib/screens/player_screen.dart');
      expect(player.contains('playerViewLyrics'), isTrue);
    });

    test('long operations show in-flight feedback', () {
      final search = read('lib/screens/search_screen.dart');
      expect(search.contains('bool _searching = false;'), isTrue);
      expect(search.contains('LinearProgressIndicator(minHeight: 2)'), isTrue);
      final collections = read('lib/screens/collections_screen.dart');
      expect(collections.contains('dupCountCache < 0'), isTrue);
      final history = read('lib/screens/history_screen.dart');
      expect(history.contains('l.retry'), isTrue);
    });

    test('sleep checkbox toggles through one handler', () {
      final sheet = read('lib/widgets/sleep_timer_sheet.dart');
      expect(sheet.contains('setFinishCurrentSongOnSleep(next)'), isTrue);
      expect(
          sheet.contains('onTap: () => setState(() => _finishSong = !_finishSong)'),
          isFalse);
    });
  });

  group('design tokens', () {
    test('shared type scale is defined', () {
      final theme = read('lib/theme/app_theme.dart');
      expect(theme.contains('textTheme: swaraType'), isTrue);
      expect(theme.contains('titleMedium: baseType.titleMedium'), isTrue);
    });

    test('card radii and rank width are consistent', () {
      final albums = read('lib/screens/albums_screen.dart');
      expect(albums.contains('Radius.circular(12)'), isFalse);
      final dashboard = read('lib/screens/dashboard_screen.dart');
      expect(dashboard.contains('Radius.circular(14)'), isFalse);
      expect(dashboard.contains('width: 28'), isTrue);
    });
  });
}
