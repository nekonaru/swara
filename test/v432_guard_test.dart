import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the deep audit fixes in v4.3.2. These are source-level checks
// plus widget/state smoke tests where a real platform player is not needed.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('empty queue pauses both players', () {
    final p = read('lib/services/player_service.dart');
    expect(p.contains('The audible player may be either one after a completed crossfade'), isTrue);
    expect(p.contains('A completed crossfade leaves the standby player audible'), isTrue);
    final empty = p.split('if (songs.isEmpty) {')[1].split('return;')[0];
    expect(empty.contains('await _player.pause()'), isTrue);
    expect(empty.contains('_crossfadePlayer?.pause()'), isTrue);
    final removed = p.split('if (nextOrder.isEmpty) {')[1].split('return;')[0];
    expect(removed.contains('await _player.pause()'), isTrue);
    expect(removed.contains('_crossfadePlayer?.pause()'), isTrue);
    expect(removed.contains('_usingCrossfadePlayer = false'), isTrue);
  });

  test('cold resume reattaches effects and external seek is guarded', () {
    final p = read('lib/services/player_service.dart');
    final resume = p
        .split('Resume path: NO volume dip')[1]
        .split('Resume position updates for crossfade triggers.')[0];
    expect(resume.contains('EqualizerService.instance.attach(target)'), isTrue);
    expect(resume.contains('LoudnessService.instance.attach(target)'), isTrue);
    expect(p.contains('Future<void> seekFromExternal(Duration position)'), isTrue);
    final seek = p.split('Future<void> seekFromExternal(Duration position)')[1].split('notifyListeners();')[0];
    expect(seek.contains('setUserSeeking(true)'), isTrue);
    expect(seek.contains('final wasSeeking = _userSeeking'), isTrue);
    expect(seek.contains('setUserSeeking(wasSeeking)'), isTrue);
    expect(seek.contains('_saveResumeState()'), isTrue);
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('PlayerService.instance.seekFromExternal(position)'), isTrue);
  });

  test('crossfade release drops the effect callback and trim is per song', () {
    final p = read('lib/services/player_service.dart');
    final release = p.split('void _releaseCrossfadePlayer() {')[1].split('return created;')[0];
    // Split starts at the release method and ends before the next method.
    final body = release.split('Future<void> _syncSpeedPitch')[0];
    expect(body.contains('_effectCrossfadeSub?.cancel()'), isTrue);
    final deleted = p.split('Paused: load the new source without playing it')[1].split('notifyListeners();')[0];
    expect(deleted.contains('applyTrimToPlayer(_player, next)'), isTrue);
    expect(p.contains('final Map<int, Song> _songByPlayer'), isTrue);
    expect(p.contains('_songByPlayer[player.hashCode] = song'), isTrue);
    final refresh = p.split('Future<void> refreshPlaybackSettings()')[1].split('Map<int, Map<String, num>>')[0];
    expect(refresh.contains('settingsFor(primarySong)'), isTrue);
    expect(refresh.contains('settingsFor(standbySong)'), isTrue);
  });

  test('media session clamps queue index and publishes actions once', () {
    final h = read('lib/services/swara_audio_handler.dart');
    expect(h.contains('final windowLength = _publishedQueueLength'), isTrue);
    expect(h.contains('relativeIndex.clamp(0, windowLength > 0 ? windowLength - 1 : 0)'), isTrue);
    final custom = h.split('Future<dynamic> customAction(String name,')[1].split('A MediaSession stop')[0];
    expect(custom.contains('_syncState();'), isFalse);
  });

  test('playlist removal replaces the cached source list', () {
    final p = read('lib/screens/playlist_detail_screen.dart');
    expect(p.contains('_songs = _songs.where((s) => s.id != song.id).toList'), isTrue);
    expect(p.contains('_songs.removeWhere('), isFalse);
  });

  test('art cache maintenance does not decompress lyrics', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('Future<List<String>> getAlbumArtPaths()'), isTrue);
    expect(db.contains('SELECT DISTINCT albumArtPath FROM songs'), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('DBHelper.instance.getAlbumArtPaths()'), isTrue);
    expect(backup.contains("'albumArtUrl': null"), isTrue);
  });

  test('backup import treats known playlists as success and normalizes time', () {
    final b = read('lib/services/backup_service.dart');
    expect(b.contains('int playlistsAlreadyPresent = 0'), isTrue);
    expect(b.contains('playlistsAlreadyPresent == 0'), isTrue);
    expect(b.contains('parsedTs.toLocal().toIso8601String()'), isTrue);
  });

  test('failed scans stay retryable and paging has no stale fast path', () {
    final l = read('lib/providers/library_provider.dart');
    expect(l.contains('if (scanError != null) return;'), isTrue);
    expect(l.contains('fetchSongsPage'), isTrue);
    expect(l.contains('songs.sublist(safeOffset, end)'), isFalse);
    expect(l.contains('_lastFullLoadAt'), isFalse);
  });

  test('artwork probes share one MediaStore client', () {
    final e = read('lib/services/embedded_art_service.dart');
    expect(e.contains('static final OnAudioQuery _query = OnAudioQuery()'), isTrue);
    expect(e.contains('await _query.queryArtwork('), isTrue);
    expect(e.contains('OnAudioQuery().queryArtwork('), isFalse);
  });

  test('tile unregisters its controller callback on suspension', () {
    final t = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraPlaybackTile.kt',
    );
    expect(t.contains('private fun unregisterControllerCallback()'), isTrue);
    final suspended = t.split('override fun onConnectionSuspended() {')[1].split('}')[0];
    final failed = t.split('override fun onConnectionFailed() {')[1].split('}')[0];
    expect(suspended.contains('unregisterControllerCallback()'), isTrue);
    expect(failed.contains('unregisterControllerCallback()'), isTrue);
  });
}
