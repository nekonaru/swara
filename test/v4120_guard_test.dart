import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.12 smart playlist and reliability release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('DB v16 carries smart playlist rules', () {
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('version: 16'), isTrue);
    expect(db.contains('rule TEXT'), isTrue);
    expect(db.contains('oldVersion < 16'), isTrue);
    expect(db.contains('Future<void> setPlaylistRule('), isTrue);
    expect(db.contains('createPlaylist(String name,'), isTrue);
  });

  test('smart rule model is whitelisted', () {
    final model = read('lib/models/smart_rule.dart');
    expect(model.contains('enum SmartField'), isTrue);
    expect(model.contains('enum SmartOp'), isTrue);
    expect(model.contains('static SmartRule? tryParse('), isTrue);
    expect(model.contains('needsPlayStats'), isTrue);
  });

  test('smart playlist service binds every value', () {
    final service = read('lib/services/smart_playlist_service.dart');
    expect(service.contains('args.add('), isTrue);
    expect(service.contains('replacePlaylistSongs('), isTrue);
    expect(service.contains('rebuildAll('), isTrue);
    expect(service.contains("'random_daily'"), isTrue);
  });

  test('smart playlists are reachable from the UI and backup', () {
    final collections = read('lib/screens/collections_screen.dart');
    expect(collections.contains('showSmartRuleEditor('), isTrue);
    expect(collections.contains('smartPlaylistNew'), isTrue);
    expect(collections.contains('edit_rule'), isTrue);
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains("'rule': (row['rule'] ?? '').toString()"), isTrue);
    expect(backup.contains('SmartPlaylistService.instance.rebuildAll()'), isTrue);
    final provider = read('lib/providers/playlist_provider.dart');
    expect(provider.contains('Future<void> createSmart('), isTrue);
  });

  test('v4.11 findings are fixed', () {
    final isolate = read('lib/services/search_isolate.dart');
    expect(isolate.contains('ready.future.then('), isTrue);
    final snapshot = read('lib/services/snapshot_service.dart');
    expect(snapshot.contains('microsecondsSinceEpoch'), isTrue);
    final settings = read('lib/screens/settings_screen.dart');
    expect(settings.contains('handle.closed.then('), isTrue);
    final db = read('lib/services/db_helper.dart');
    final markPlayed = db.split('Future<void> markPlayed(int songId)')[1].split('Future<void>')[0];
    expect(markPlayed.indexOf('invalidateDashboardCache()') >
        markPlayed.indexOf('database.update('), isTrue);
    expect(read('lib/utils/backup_paths.dart').contains('Uri.decodeFull'), isTrue);
    expect(read('lib/services/db_helper.dart').contains('normalizeBackupPath(path)'), isTrue);
  });

  test('smart l10n keys exist in both locales', () {
    for (final name in ['app_en.arb', 'app_id.arb']) {
      final arb = read('lib/l10n/$name');
      for (final key in [
        'smartPlaylistNew',
        'smartRuleTitle',
        'smartRuleSummary',
        'smartRuleInvalid',
      ]) {
        expect(arb.contains('"$key"'), isTrue, reason: '$name missing $key');
      }
    }
  });
}
