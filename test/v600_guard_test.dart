import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v6 feature release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  bool backupContainsPreview(String text) =>
      text.contains('previewBackup(') && text.contains('int unmatched');

  test('v18 schema carries ratings and v6 helpers', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('version: 18'), isTrue);
    expect(db.contains('rating INTEGER DEFAULT 0'), isTrue);
    expect(db.contains('Future<void> setRating('), isTrue);
    expect(db.contains('Future<void> mergeLabels('), isTrue);
    expect(db.contains('Future<List<Song>> getRatedSongs('), isTrue);
    expect(db.contains('Future<List<Song>> getSongsByLabel('), isTrue);
    expect(backupContainsPreview(read('lib/services/backup_service.dart')),
        isTrue);
    expect(read('lib/services/backup_service.dart').contains("'rating': song.rating"),
        isTrue);
  });

  test('ratings and label tools are reachable', () {
    final song = read('lib/models/song.dart');
    expect(song.contains('int rating;'), isTrue);
    for (final file in [
      'lib/screens/edit_metadata_screen.dart',
      'lib/screens/bulk_edit_screen.dart',
      'lib/screens/edit_lyrics_screen.dart',
    ]) {
      expect(read(file).contains('rating: s.rating'), isTrue, reason: file);
    }
    final options = read('lib/utils/song_options.dart');
    expect(options.contains('V6.rate'), isTrue);
    expect(options.contains('V6.similarSongs'), isTrue);
    final manager = read('lib/screens/label_manager_screen.dart');
    expect(manager.contains('renameLabel(label,'), isTrue);
    expect(manager.contains('mergeLabels(label,'), isTrue);
    final extras = read('lib/screens/v5_extras_screen.dart');
    expect(extras.contains('const LabelManagerScreen()'), isTrue);
    expect(extras.contains('const InsightsScreen()'), isTrue);
  });

  test('playback gains fair shuffle, modes and Auto DJ', () {
    final player = read('lib/services/player_service.dart');
    expect(player.contains('bool _fairShuffle = false;'), isTrue);
    expect(player.contains('Future<void> setFairShuffle('), isTrue);
    expect(player.contains('_spreadArtists(order)'), isTrue);
    final library = read('lib/screens/library_screen.dart');
    expect(library.contains('Future<void> _autoDj('), isTrue);
    expect(library.contains('Future<void> _playOrdered('), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('V6.shuffleFair'), isTrue);
  });

  test('discovery and integrations are wired', () {
    final service = read('lib/services/extra_features_service.dart');
    expect(service.contains('class SimilarSongsService'), isTrue);
    final insights = read('lib/screens/insights_screen.dart');
    expect(insights.contains('V6.exportCsv'), isTrue);
    final catalog = read('lib/services/swara_browse_catalog.dart');
    for (final id in ['catRated', 'catLabels', 'catHistory', 'labelPrefix']) {
      expect(catalog.contains(id), isTrue, reason: id);
    }
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains("lower == 'unplayed'"), isTrue);
    expect(handler.contains('excludedFolders: excluded'), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('BackupService.previewBackup(raw)'), isTrue);
  });

  test('v6 strings exist in both languages', () {
    final en = read('lib/l10n/app_en.arb');
    final id = read('lib/l10n/app_id.arb');
    // v6 strings live in one bilingual helper, selected from LanguageProvider.
    final strings = read('lib/l10n/v6_strings.dart');
    expect(strings.contains('static bool get id => LanguageProvider.instance.isIndonesian;'),
        isTrue);
    expect(strings.contains("static String get rate => id ? 'Beri rating' : 'Rate';"),
        isTrue);
    expect(en.isNotEmpty && id.isNotEmpty, isTrue);
  });
}
