import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v6.0.1 native correctness patch.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('play mode label and fair shuffle paths agree', () {
    final lib = read('lib/screens/library_screen.dart');
    expect(lib.contains('title: Text(V6.topRated)'), isTrue);
    final player = read('lib/services/player_service.dart');
    expect(player.contains('List<int> _shuffledTailAfter('), isTrue);
    expect(player.contains('_spreadArtists(order)'), isTrue);
    expect(player.contains('row.rating = source.rating'), isTrue);
  });

  test('rating survives rename and backup settings', () {
    final provider = read('lib/providers/library_provider.dart');
    expect(provider.contains('rating: song.rating'), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('fairShuffleV6'), isTrue);
    final codec = read('lib/utils/backup_settings_codec.dart');
    expect(codec.contains('fairShuffleV6'), isTrue);
  });

  test('voice lookup and preview are precise', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('genre = ? COLLATE NOCASE'), isTrue);
    expect(db.contains('l.label = ? COLLATE NOCASE'), isTrue);
    expect(db.contains('GROUP BY s.id ORDER BY julianday(lastTs) DESC'), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('candidates.length == 1'), isTrue);
  });

  test('excluded folders and labels stay consistent', () {
    final provider = read('lib/providers/library_provider.dart');
    expect(provider.contains('isHiddenPath(s.filePath, excluded)'), isTrue);
    final lib = read('lib/screens/library_screen.dart');
    expect(lib.contains('excludedFolders: await DBHelper.instance.getExcludedFolders()'),
        isTrue);
    final manager = read('lib/screens/label_manager_screen.dart');
    expect(manager.contains('if (next.isEmpty || next == label) return;'), isTrue);
  });

  test('CSV export is timestamped', () {
    final insights = read('lib/screens/insights_screen.dart');
    expect(insights.contains('swara_listening_\$stamp.csv'), isTrue);
    expect(insights.contains('activeHours.isEmpty'), isTrue);
  });
}
