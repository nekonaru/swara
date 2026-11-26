import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.19 explicit-consent release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('no destructive work runs automatically at boot or scan', () {
    final scanner = read('lib/services/library_scanner.dart');
    expect(scanner.contains('deleteSongsMissingFromDevice('), isFalse);
    final main = read('lib/main.dart');
    expect(main.contains('pruneMetadataCache('), isFalse);
    final snapshot = read('lib/services/snapshot_service.dart');
    expect(snapshot.contains('snapshots.skip(maxSnapshots)'), isFalse);
    final import = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/'
      'SwaraAudioImport.kt',
    );
    expect(import.contains('contentResolver.delete(target'), isFalse);
  });

  test('every user deletion asks for confirmation', () {
    final settings = read('lib/screens/settings_screen.dart');
    for (final needle in [
      'Future<void> _deleteSnapshot(',
      'Future<void> _pruneOldSnapshots()',
    ]) {
      expect(settings.contains(needle), isTrue);
    }
    expect(settings.contains('showDialog<bool>'), isTrue);
    final playlist = read('lib/screens/playlist_detail_screen.dart');
    expect(playlist.contains('playlistRemoveConfirmTitle'), isTrue);
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('destructiveConfirmMessage'), isTrue);
    final sheet = read('lib/widgets/playback_settings_sheet.dart');
    expect(sheet.contains('destructiveConfirmTitle'), isTrue);
    final bulk = read('lib/screens/bulk_edit_screen.dart');
    expect(bulk.contains('destructiveUpdateMessage'), isTrue);
    final lyrics = read('lib/screens/edit_lyrics_screen.dart');
    expect(lyrics.contains('hadLrc'), isTrue);
    final queue = read('lib/screens/queue_screen.dart');
    expect(queue.contains('destructiveConfirmMessage'), isTrue);
  });

  test('snapshot deletion validates the name against the known list', () {
    final snapshot = read('lib/services/snapshot_service.dart');
    expect(snapshot.contains('deleteSnapshots(List<String> names)'), isTrue);
    expect(snapshot.contains('RegExp(r\'^swara-snapshot-'), isTrue);
    expect(snapshot.contains('any((s) => s.name == name)'), isTrue);
  });

  test('new consent strings exist in both locales', () {
    for (final path in [
      'lib/l10n/app_en.arb',
      'lib/l10n/app_id.arb',
    ]) {
      final text = read(path);
      expect(text.contains('destructiveConfirmTitle'), isTrue);
      expect(text.contains('destructiveUpdateMessage'), isTrue);
      expect(text.contains('dataSnapshotPruneMessage'), isTrue);
      expect(text.contains('playlistRemoveConfirmMessage'), isTrue);
    }
  });
}
