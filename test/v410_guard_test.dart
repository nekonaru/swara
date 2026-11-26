import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.1 playback-settings feature and backup round-trip.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('v13 schema carries both override tables and cascades', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('version: 17'), isTrue);
    expect(db.contains('CREATE TABLE song_playback_settings'), isTrue);
    expect(db.contains('CREATE TABLE folder_playback_settings'), isTrue);
    expect(db.contains('CREATE TABLE IF NOT EXISTS song_playback_settings'), isTrue);
    final deletes = db.split('deleteSong(int id)')[1].split('Future<void> updateSongMetadata')[0];
    expect(deletes.contains('song_playback_settings'), isTrue);
  });

  test('all volume writes go through the trim choke point', () {
    final player = read('lib/services/player_service.dart');
    expect(player.contains('Future<void> _setVol('), isTrue);
    expect(player.contains('player.setVolume((base *'), isTrue);
    expect(player.contains('skipStartMs'), isTrue);
    expect(player.contains('_effectiveEnd'), isTrue);
  });

  test('backup carries and restores settings', () {
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains("'playback_settings':"), isTrue);
    expect(backup.contains('songSettingsRestored'), isTrue);
    expect(backup.contains('version > kBackupFormatVersion'), isTrue);
    expect(backup.contains('dataImportFile'), isFalse); // UI key lives in settings
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('dataImportFile'), isTrue);
  });

  test('MediaSession active item follows the published window', () {
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('playbackState.add(playbackState.value.copyWith(queueIndex: active))'), isTrue);
  });

  test('sleep crossfade cannot play an extra partial song', () {
    final player = read('lib/services/player_service.dart');
    expect(player.contains('if (_pendingSleepStop || sleepSongsRemaining == 1) return;'), isTrue);
  });
}
