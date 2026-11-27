import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v5.1.2 player layout and native correctness patch.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('player uses labelled controls and keeps the queue reachable', () {
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('Widget _labelledControl('), isTrue);
    expect(player.contains('BoxConstraints(minHeight: 48)'), isTrue);
    expect(player.contains('Icons.queue_music_outlined'), isTrue);
    expect(player.contains('V5.more'), isTrue);
    expect(player.contains('Future<void> _showMoreSheet('), isTrue);
    // The secondary row is no longer a single Row of eight bare icons.
    final controls = player.split('Widget _buildControls(')[1].split('/// Repeat button')[0];
    expect(controls.contains('ListenableBuilder('), isTrue);
    expect(controls.contains('ActionChip('), isFalse);
  });

  test('multi-select bar wraps instead of clipping', () {
    final lib = read('lib/screens/library_screen.dart');
    final bar = lib
        .split('Widget _buildMultiSelectBar(')[1]
        .split('Widget _buildSortHeader(')[0];
    expect(bar.contains('child: Wrap('), isTrue);
    expect(bar.contains('const Spacer()'), isFalse);
    expect(lib.contains('V5.trashConfirm(l.librarySelectedCount('), isTrue);
  });

  test('widget queue length accepts every value in range', () {
    final service = read('lib/services/extra_features_service.dart');
    expect(service.contains('return value.clamp(3, 8);'), isTrue);
    expect(service.contains('await prefs.setInt(_queueKey, length.clamp(3, 8));'),
        isTrue);
  });

  test('trash survives rescan and labels survive backup', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('Future<Set<String>> getTrashedPaths()'), isTrue);
    final scanner = read('lib/services/library_scanner.dart');
    expect(scanner.contains('getTrashedPaths()'), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains("'label': labelById[song.id] ?? ''"), isTrue);
    expect(backup.contains('final labelById = await DBHelper.instance.getSongLabels();'),
        isTrue);
  });

  test('lyrics stamping and Auto browse respect their scope', () {
    final lyrics = read('lib/screens/edit_lyrics_screen.dart');
    expect(lyrics.contains('widget.song.id) {'), isTrue);
    final catalog = read('lib/services/swara_browse_catalog.dart');
    expect(catalog.contains('excludedFolders: excluded'), isTrue);
    final search = read('lib/screens/search_screen.dart');
    expect(search.contains('Text(V5.all)'), isTrue);
  });
}
