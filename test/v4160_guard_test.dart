import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.16 playback and reliability release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('Next on the last song keeps playback alive', () {
    final p = read('lib/services/player_service.dart');
    final next = p.split('  Future<void> next() async {')[1].split('  Future<void> previous()')[0];
    expect(next.indexOf('return;') < next.indexOf('await _vol('), isTrue);
    expect(next.contains('await _playCurrent();'), isTrue);
  });

  test('queue access is constant time on notify paths', () {
    final p = read('lib/services/player_service.dart');
    expect(p.contains('Song? songAtOrderIndex(int index)'), isTrue);
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('ps.queueOrderLength'), isTrue);
    final main = read('lib/main.dart');
    expect(main.contains('service.songAtOrderIndex(i)'), isTrue);
    final queue = read('lib/screens/queue_screen.dart');
    expect(queue.contains('_removeSlot(int slotId, String path)'), isTrue);
    expect(queue.contains('song.filePath)'), isTrue);
  });

  test('play-stat smart rebuilds are throttled', () {
    final s = read('lib/services/smart_playlist_service.dart');
    expect(s.contains('_lastPlayStatsRebuild'), isTrue);
    expect(s.contains('Duration(minutes: 2)'), isTrue);
  });

  test('repeat-one crossfade rebinds the lyric follower', () {
    final p = read('lib/screens/player_screen.dart');
    expect(p.contains('final flipped = _lrcFlipCount != _player.playbackFlipCount'), isTrue);
    expect(p.contains('_lrcSongId = -1;'), isTrue);
  });

  test('voice metadata outranks a broad spoken query', () {
    final h = read('lib/services/swara_audio_handler.dart');
    final search = h.split('Future<void> playFromSearch(')[1].split('    } catch (e)')[0];
    expect(search.indexOf("'\$artist \$title'") < search.indexOf('query.trim()'), isTrue);
  });

  test('LRC import mutates the song only after a successful DB write', () {
    final service = read('lib/services/lrc_import_service.dart');
    expect(service.contains('Future<({int count, String plain})> pickAndApply'), isTrue);
    expect(service.contains('song.lyrics ='), isFalse);
    final screen = read('lib/screens/edit_lyrics_screen.dart');
    expect(screen.contains('lyrics: imported.plain'), isTrue);
  });

  test('share import never deletes a pre-existing MediaStore row', () {
    final kt = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraAudioImport.kt',
    );
    expect(kt.contains('stalePending'), isFalse);
    expect(kt.contains('context.contentResolver.delete(uri, null, null)'), isFalse);
    expect(kt.contains('if (committed) return CopyResult(Outcome.DUPLICATE)'), isTrue);
  });
}
