import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guards for the manual-only metadata scan and its stop control.
///
/// The metadata scan used to start on its own a few seconds after startup and
/// could not be interrupted, so a scan burned data and rate limit budget
/// without anyone asking for it and left no way out once it began. These
/// guards pin the two halves of the fix: no screen may start a scan by
/// itself, and every bulk scan entry point must offer a stop.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('startup never starts a metadata scan on its own', () {
    final source = read('lib/screens/home_screen.dart');
    expect(
      source.contains('bulkScanMetadata'),
      isFalse,
      reason: 'the home screen must only load from the DB and scan local '
          'files; fetching metadata from the internet is triggered by the '
          'user and never by a timer at startup',
    );
  });

  test('the provider exposes a cancel that the batch loop obeys', () {
    final source = read('lib/providers/library_provider.dart');
    expect(
      source.contains('Future<void> cancelBulkScan()'),
      isTrue,
      reason: 'a running bulk metadata scan must be stoppable, so the '
          'provider needs a cancel entry point',
    );
    // The loop body itself must honour the request, not just the flag
    // existing somewhere in the file.
    final loop = source.split('Future<void> _runBulkScan(')[1];
    expect(
      loop.contains('if (_bulkScanCancelRequested) break;'),
      isTrue,
      reason: 'the batch loop must check the cancel flag before starting the '
          'next batch, otherwise the stop button would do nothing',
    );
    expect(
      loop.contains('isBulkScanningMetadata = false'),
      isTrue,
      reason: 'a cancelled scan must still clear the running flags, or the UI '
          'would stay stuck on the progress state forever',
    );
  });

  test('the library and settings screens can stop a running scan', () {
    for (final path in [
      'lib/screens/library_screen.dart',
      'lib/screens/settings_screen.dart',
    ]) {
      final source = read(path);
      expect(
        source.contains('stopBulkMetadataScan('),
        isTrue,
        reason: '$path offers a running scan but must also offer a way to '
            'end it',
      );
    }
  });

  test('the per screen bulk fetches can be interrupted too', () {
    for (final path in [
      'lib/screens/missing_art_screen.dart',
      'lib/screens/missing_lyrics_screen.dart',
      'lib/screens/extra_screens.dart',
    ]) {
      final source = read(path);
      // Matched case insensitively: the per screen flag is _cancelRequested,
      // the folder screen names its own _scanCancelRequested. The pattern
      // requires a conditional ON the flag, so a stray mention elsewhere in
      // the file cannot satisfy it.
      expect(
        RegExp(r'if \(\w*[cC]ancelRequested\)').hasMatch(source),
        isTrue,
        reason: '$path runs a bulk enrich loop and must check a cancel flag '
            'so the user can stop it',
      );
    }
  });

  test('stopping keeps the metadata that was already fetched', () {
    // enrichSong writes each song as it completes, so a stop only decides
    // how many songs are still missing, never throws work away.
    final source = read('lib/services/metadata_service.dart');
    expect(
      source.contains('await DBHelper.instance.upsertSong(song);'),
      isTrue,
      reason: 'every enriched song must be persisted on its own, otherwise a '
          'cancelled scan would lose everything it fetched before the stop',
    );
  });
}
