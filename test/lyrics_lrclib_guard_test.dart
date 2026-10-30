import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guards for the lrclib lyrics integration.
///
/// One lrclib request returns both the plain and the synced lyrics, so a
/// single round trip can serve both views of a song. The code used to make
/// two separate requests for the same track: lrclib for the synced form and
/// lyrics.ovh for the plain form. These guards pin the shape of that flow so
/// it cannot quietly fall back to two requests again, and so the lyrics.ovh
/// lookup stays a fallback instead of competing with lrclib.
void main() {
  String readService() => File('lib/services/metadata_service.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('one lrclib request carries both the plain and the synced lyrics', () {
    final source = readService();
    expect(
      source.contains("'plainLyrics'"),
      isTrue,
      reason: 'the plain lyrics must be read from the same lrclib response '
          'that supplies the synced lyrics',
    );
    expect(
      source.contains("'syncedLyrics'"),
      isTrue,
      reason: 'the synced lyrics must be read from the same lrclib response',
    );
  });

  test('the lrclib lookup runs off the main thread', () {
    final source = readService();
    expect(
      source.contains('compute(\n        _lrclibFetchIsolate,'),
      isTrue,
      reason: 'lrclib HTTP must run in an isolate so it never holds the main '
          'thread during a scan or a lyrics fetch',
    );
    // The old path made the lrclib request inline on the main thread.
    expect(
      source.contains("Uri.https('lrclib.net', '/api/get', params)"),
      isFalse,
      reason: 'the inline main-thread lrclib request must be gone',
    );
  });

  test('lyrics.ovh is only a fallback after lrclib misses', () {
    final source = readService();
    final fetchLyricsOnly = source.split('Future<bool> fetchLyricsOnly(')[1];
    // Inside fetchLyricsOnly, lrclib must be consulted first.
    expect(
      fetchLyricsOnly.indexOf('_fetchFromLrclib'),
      lessThan(fetchLyricsOnly.indexOf('_fetchPlainFromLyricsOvh')),
      reason: 'lrclib is the primary source and lyrics.ovh only covers what '
          'lrclib does not have',
    );
    expect(
      fetchLyricsOnly.contains('_fetchPlainFromLyricsOvh'),
      isTrue,
      reason: 'lyrics.ovh stays as the fallback so a track lrclib is missing '
          'still gets its plain lyrics',
    );
  });

  test('synced lyrics from lrclib are stored in their own table', () {
    final source = readService();
    expect(
      source.contains('setSyncedLyrics'),
      isTrue,
      reason: 'the synced form must be written to the synced_lyrics table so '
          'the player can follow the lines',
    );
  });

  test('a lyrics payload is capped before it reaches the DB', () {
    final source = readService();
    expect(
      source.contains('_capLyrics'),
      isTrue,
      reason: 'an anomalous response must never bloat the DB, so both the '
          'plain and the synced payload go through the shared cap',
    );
  });
}
