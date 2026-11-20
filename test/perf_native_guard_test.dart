import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v3.12.1 optimization pass: no new features, only native
// feel, lightness and smoothness of the existing ones. Pin the fixes so a
// refactor cannot silently restore O(n^2) work or iOS-style navigation.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  group('large queues stay light', () {
    test('clear up next removes the tail in one pass', () {
      final player = read('lib/services/player_service.dart');
      expect(player.contains('Future<int> removeQueueTail'), isTrue);
      final screen = read('lib/screens/queue_screen.dart');
      expect(screen.contains('_player.removeQueueTail(last)'), isTrue);
      expect(screen.contains('final queueLength = _player.queue.length'), isTrue);
      expect(screen.contains('for (var i = _player.queue.length'), isFalse);
    });

    test('save queue as playlist uses one batched insert', () {
      final screen = read('lib/screens/queue_screen.dart');
      expect(screen.contains('prov.addSongs('), isTrue);
      expect(screen.contains('await prov.load();'), isTrue);
      expect(screen.contains('await prov.addSong(playlistId, song.id)'), isFalse);
    });

    test('MediaSession publishes a bounded window', () {
      final handler = read('lib/services/swara_audio_handler.dart');
      expect(handler.contains('_queueWindowTotal = 40'), isTrue);
      expect(handler.contains('currentIndex - _queueWindowStart'), isTrue);
      expect(handler.contains('published[index].id.split'), isTrue);
    });
  });

  group('database reads stay narrow', () {
    test('dashboard loads summaries and only ten full songs', () {
      final dashboard = read('lib/screens/dashboard_screen.dart');
      expect(dashboard.contains('getSongSummaries()'), isTrue);
      expect(dashboard.contains('getSongsByIds(lookupIds)'), isTrue);
      expect(dashboard.contains('DBHelper.instance.getAllSongs()'), isFalse);
    });

    test('duplicate counting crosses the isolate as compact rows', () {
      final collections = read('lib/screens/collections_screen.dart');
      final duplicates = read('lib/screens/duplicates_screen.dart');
      expect(collections.contains("'duration': s.durationMs"), isTrue);
      expect(duplicates.contains('countDuplicateGroupsFromRows'), isTrue);
    });
  });

  group('native navigation and polish', () {
    test('Android uses the shared Material transition everywhere', () {
      final theme = read('lib/theme/app_theme.dart');
      expect(theme.contains("import 'package:flutter/cupertino.dart'"), isFalse);
      expect(theme.contains('TargetPlatform.iOS'), isFalse);
      for (final name in [
        'lib/screens/albums_screen.dart',
        'lib/screens/collections_screen.dart',
        'lib/screens/extra_screens.dart',
      ]) {
        final source = read(name);
        expect(source.contains('Offset(1, 0)'), isFalse,
            reason: '$name still uses an iOS-style push');
      }
    });

    test('touch targets meet Android minimums', () {
      final chip = read('lib/widgets/sort_chip.dart');
      expect(chip.contains('BoxConstraints(minHeight: 48)'), isTrue);
      final settings = read('lib/screens/settings_screen.dart');
      expect(settings.contains('InkWell('), isTrue);
    });
  });

  group('stability anomalies', () {
    test('deleting the paused song reloads the new source', () {
      final player = read('lib/services/player_service.dart');
      expect(player.contains('await _player.setFilePath(next.filePath)'), isTrue);
    });

    test('boot-time restore errors reach the user', () {
      final home = read('lib/screens/home_screen.dart');
      expect(home.contains('_lastPlayerErrorShown = null;'), isTrue);
      expect(home.contains('if (mounted) _playbackErrorListener();'), isTrue);
    });

    test('effect session broadcasts have timeouts', () {
      final eq = read('lib/services/equalizer_service.dart');
      expect(eq.contains('openAudioEffectSession(sessionId).timeout'), isTrue);
      expect(eq.contains('closeAudioEffectSession(sessionId).timeout'), isTrue);
    });
  });
}
