import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swara/theme/app_theme.dart';

// Guards for the v4.4 cold start, contrast, typography and audit fixes.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('dark and light text themes come from the active color scheme', () {
    final theme = read('lib/theme/app_theme.dart');
    expect(theme.contains('Typography.material2021()'), isFalse);
    expect(theme.contains('textTheme: swaraType'), isFalse);
    expect(theme.contains('Let ThemeData build the Material 3 text theme'), isTrue);

    final dark =
        buildSwaraTheme(seed: Colors.blue, brightness: Brightness.dark);
    final light =
        buildSwaraTheme(seed: Colors.blue, brightness: Brightness.light);
    final darkBody = dark.textTheme.bodyMedium?.color;
    final lightBody = light.textTheme.bodyMedium?.color;
    expect(darkBody, isNotNull);
    expect(lightBody, isNotNull);
    expect(darkBody!.computeLuminance(), greaterThan(0.5));
    expect(lightBody!.computeLuminance(), lessThan(0.5));
  });

  test('text scale uses small normal large with a normal default', () {
    final provider = read('lib/providers/theme_provider.dart');
    expect(provider.contains('kTextScaleSmall = 0.85'), isTrue);
    expect(provider.contains('kTextScaleNormal = 1.0'), isTrue);
    expect(provider.contains('kTextScaleLarge = 1.15'), isTrue);
    expect(provider.contains('double textScale = kTextScaleNormal'), isTrue);
    expect(provider.contains("'textScaleV2'"), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('value: kTextScaleSmall'), isTrue);
    expect(settings.contains('value: kTextScaleNormal'), isTrue);
    expect(settings.contains('value: kTextScaleLarge'), isTrue);
  });

  test('boot has no artificial delay and home builds lazily', () {
    final main = read('lib/main.dart');
    expect(main.contains('No artificial floor here'), isTrue);
    expect(main.contains('Duration(milliseconds: 600)'), isFalse);
    expect(main.contains('Duration(milliseconds: 220)'), isTrue);
    final home = read('lib/screens/home_screen.dart');
    expect(home.contains('_groupIndex == 1 ? const CollectionsScreen()'), isTrue);
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('Future<Database>? _dbFuture'), isTrue);
    final player = read('lib/services/player_service.dart');
    expect(player.contains('unawaited(_restoreAfterBoot())'), isTrue);
  });

  test('primary content uses readable font sizes', () {
    final library = read('lib/screens/library_screen.dart');
    expect(library.contains('fontSize: 16'), isTrue);
    final theme = read('lib/theme/app_theme.dart');
    expect(theme.contains('labelStyle: const TextStyle(fontSize: 14'), isTrue);
    final eq = read('lib/widgets/eq_controls.dart');
    expect(eq.contains('fontSize: 11'), isTrue);
  });

  test('lyrics refresh keeps manual metadata', () {
    final screen = read('lib/screens/missing_lyrics_screen.dart');
    expect(screen.contains('_fetchLyricsKeepingMetadata'), isTrue);
    expect(screen.contains('song.title = title'), isTrue);
    expect(screen.contains('enrichSong(song, bypassCache: true)'), isTrue);
  });

  test('bulk scan retries a backoff batch instead of dropping it', () {
    final lib = read('lib/providers/library_provider.dart');
    expect(lib.contains('i -= batchSize'), isTrue);
  });

  test('M3U paths are canonical and import names stay unique', () {
    final m3u = read('lib/services/m3u_service.dart');
    expect(m3u.contains('p.posix.normalize'), isTrue);
    final collections = read('lib/screens/collections_screen.dart');
    expect(collections.contains('existingNames.contains(name)'), isTrue);
  });

  test('dashboard cache is invalidated by new listening entries', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('static Future<void> invalidateDashboardCache()'), isTrue);
    final player = read('lib/services/player_service.dart');
    expect(player.contains('then((_) => DBHelper.invalidateDashboardCache())'), isTrue);
  });

  test('EQ draft and lyrics found state follow live data', () {
    final eq = read('lib/widgets/eq_controls.dart');
    expect(eq.contains('_lastPresetToken'), isTrue);
    expect(eq.contains('_resetEqDraft()'), isTrue);
    final player = read('lib/screens/player_screen.dart');
    expect(player.contains('if (_lrcLines.isNotEmpty) found = true'), isTrue);
  });
}
