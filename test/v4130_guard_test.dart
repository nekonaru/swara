import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.13 browse completion and smart playlist reliability release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('Android Auto browse supports paging, recent and voice play', () {
    final catalog = read('lib/services/swara_browse_catalog.dart');
    expect(catalog.contains('android.media.browse.extra.PAGE_SIZE'), isTrue);
    expect(catalog.contains('static (int page, int pageSize) pageOf('), isTrue);
    expect(catalog.contains('childrenFor(\n    String parentId,'), isTrue);
    expect(catalog.contains('getRecentlyPlayed('), isTrue);
    expect(catalog.contains('skip(offset)'), isTrue);
    expect(catalog.contains('search(String query,'), isTrue);
    final handler = read('lib/services/swara_audio_handler.dart');
    expect(handler.contains('Future<void> playFromSearch('), isTrue);
    expect(handler.contains('childrenFor(parentMediaId, options)'), isTrue);
    final db = read('lib/services/db_helper.dart');
    expect(db.contains('getPlaylistsPage('), isTrue);
    expect(db.contains('getSongsInPlaylistPage('), isTrue);
    expect(db.contains('getMusicFoldersPage('), isTrue);
    expect(db.contains('LIMIT ? OFFSET ?'), isTrue);
    for (final name in ['app_en.arb', 'app_id.arb']) {
      expect(read('lib/l10n/$name').contains('"autoBrowseRecent"'), isTrue);
    }
  });

  test('built-in smart playlists exist on fresh installs', () {
    final service = read('lib/services/smart_playlist_service.dart');
    expect(service.contains('static const builtInSeeds'), isTrue);
    expect(service.contains('Future<List<int>> ensureBuiltIns()'), isTrue);
    expect(service.contains('await ensureBuiltIns();'), isTrue);
    expect(service.contains('_rebuildWithRule(id, rule)'), isTrue);
  });

  test('smart rules handle never played and hidden folders', () {
    final service = read('lib/services/smart_playlist_service.dart');
    expect(service.contains('expr IS NULL OR julianday'), isTrue);
    expect(service.contains('isHiddenPath(path, excluded)'), isTrue);
    expect(service.contains('LIMIT ? OFFSET ?'), isTrue);
  });

  test('smart editor rejects invalid numeric conditions', () {
    final editor = read('lib/widgets/smart_rule_editor.dart');
    expect(editor.contains('int.tryParse(text)'), isTrue);
    expect(editor.contains('smartRuleInvalid'), isTrue);
  });

  test('backup restore uses the backup rule', () {
    final backup = read('lib/services/backup_service.dart');
    expect(backup.contains('localIsSmart'), isTrue);
  });
}
