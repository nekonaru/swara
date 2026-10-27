import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guards for a data loss bug found in the third audit.
///
/// 1. The scanner used to write every row with ConflictAlgorithm.replace from
///    an object that carries no genre, art, lyrics or region. SQLite REPLACE
///    deletes the old row first, so every rescan (pull to refresh, or the
///    automatic one on app start) blanked out every enriched cover and genre.
///    Existing rows must only receive file facts.
/// 2. Two overlapping scans compared the songs table against their own
///    device snapshot, so the slower one deleted the songs the faster one had
///    just inserted, together with their playlist entries and history.
void main() {
  String readScanner() =>
      File('lib/services/library_scanner.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
  String readDb() => File('lib/services/db_helper.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  String readProvider() => File('lib/providers/library_provider.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('an existing song is updated, never replaced with a blank row', () {
    final source = readScanner();
    expect(
      source.contains("batch.update(\n          'songs',"),
      isTrue,
      reason: 'existing rows must go through update with file facts only',
    );
    // The replace is still correct for brand new songs, so it may stay, but
    // it must not be the only write path used for every track.
    final replaces = RegExp(r'ConflictAlgorithm\.replace').allMatches(source).length;
    expect(replaces, lessThanOrEqualTo(1));
  });

  test('the scanner keeps the rich columns it used to wipe', () {
    final source = readScanner();
    // A full row write for existing songs would need these to be carried
    // over from the DB snapshot. The row must instead be updated narrowly.
    expect(
      source.contains("map['genre']"),
      isFalse,
      reason: 'no manual merge of rich columns into a replacement row',
    );
    expect(
      source.contains("'filePath': song.filePath"),
      isTrue,
      reason: 'only the file facts are refreshed on an existing row',
    );
  });

  test('scanDevice has a reentrancy guard', () {
    final source = readProvider();
    expect(
      source.contains('if (_scanning) return;'),
      isTrue,
      reason: 'a second scan must be ignored while one is running',
    );
  });

  test('the ghost cleanup compares against a snapshot, not a live read', () {
    final source = readScanner();
    expect(
      source.contains('knownDbIds: dbIdsAtScanStart'),
      isTrue,
      reason: 'the delete must use the ids captured before querySongs',
    );
    final db = readDb();
    expect(db.contains('Set<int>? knownDbIds'), isTrue);
    expect(
      db.contains('knownDbIds ??'),
      isTrue,
      reason: 'the caller snapshot must win over a live table read',
    );
  });

  test('a deliberate rescan persists the enriched metadata', () {
    final db = readDb();
    expect(
      db.contains('applyEnrichedMetadata'),
      isTrue,
      reason: 'upsertSong refuses to overwrite rich columns, so the manual '
          'rescan needs its own write path',
    );
    final provider = readProvider();
    expect(provider.contains('applyEnrichedMetadata(song)'), isTrue);
    // The manual action must also skip the cache, otherwise it silently
    // replays a response that can be 30 days old.
    expect(provider.contains('bypassCache: true'), isTrue);
  });
}