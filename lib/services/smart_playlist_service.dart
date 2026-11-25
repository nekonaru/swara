import 'dart:math';

import '../models/smart_rule.dart';
import '../utils/format.dart';
import 'db_helper.dart';

/// Evaluates rule-based playlists entirely from the local database. Every
/// field and operator is whitelisted and every value is bound, so user text
/// can never become SQL.
class SmartPlaylistService {
  SmartPlaylistService._();
  static final SmartPlaylistService instance = SmartPlaylistService._();

  static const String _textFields = 'title artist album genre';

  static String _expression(SmartField field) => switch (field) {
        SmartField.title => "lower(coalesce(s.title,''))",
        SmartField.artist => "lower(coalesce(s.artist,''))",
        SmartField.album => "lower(coalesce(s.album,''))",
        SmartField.genre => "lower(coalesce(s.genre,''))",
        SmartField.favorite => 's.isFavorite',
        SmartField.playCount =>
          '(SELECT COUNT(*) FROM listening_entries le WHERE le.songId = s.id)',
        SmartField.lastPlayed => 's.lastPlayedAt',
        SmartField.addedAt => 's.addedAt',
        SmartField.duration => 's.durationMs',
      };

  static String? _clause(SmartCriterion c, List<Object?> args) {
    final expr = _expression(c.field);
    final textOps = _textFields.split(' ').contains(c.field.name);
    if (textOps) {
      final value = c.value?.toString().toLowerCase().trim() ?? '';
      if (value.isEmpty) return null;
      switch (c.op) {
        case SmartOp.contains:
          args.add(value);
          return 'instr($expr, ?) > 0';
        case SmartOp.equals:
          args.add(value);
          return '$expr = ?';
        case SmartOp.startsWith:
          args.add(value);
          args.add(value);
          return 'substr($expr, 1, length(?)) = ?';
        case SmartOp.notContains:
          args.add(value);
          return 'instr($expr, ?) = 0';
        default:
          return null;
      }
    }
    switch (c.field) {
      case SmartField.favorite:
        return switch (c.op) {
          SmartOp.isTrue => 's.isFavorite = 1',
          SmartOp.isFalse => 's.isFavorite = 0',
          _ => null,
        };
      case SmartField.lastPlayed:
      case SmartField.addedAt:
        if (c.op == SmartOp.isNull) return '$expr IS NULL';
        if (c.op == SmartOp.isNotNull) return '$expr IS NOT NULL';
        final days = (c.value as num?)?.toInt();
        if (days == null || days < 0) return null;
        args.add(days);
        if (c.op == SmartOp.beforeDays) {
          return "julianday($expr) < julianday('now', '-' || ? || ' days')";
        }
        if (c.op == SmartOp.afterDays) {
          return "julianday($expr) > julianday('now', '-' || ? || ' days')";
        }
        return null;
      default:
        final value = (c.value as num?)?.toInt();
        if (value == null || value < 0) return null;
        args.add(value);
        return switch (c.op) {
          SmartOp.eq => '$expr = ?',
          SmartOp.neq => '$expr != ?',
          SmartOp.gt => '$expr > ?',
          SmartOp.gte => '$expr >= ?',
          SmartOp.lt => '$expr < ?',
          SmartOp.lte => '$expr <= ?',
          _ => null,
        };
    }
  }

  Future<List<int>> evaluate(SmartRule rule) async {
    final database = await DBHelper.instance.db;
    final where = <String>[];
    final args = <Object?>[];
    for (final criterion in rule.criteria) {
      final clause = _clause(criterion, args);
      if (clause == null) return const <int>[];
      where.add(clause);
    }
    final order = switch (rule.order) {
      'title_desc' => 's.title DESC',
      'added_desc' => 's.addedAt DESC',
      'lastPlayed_asc' => 's.lastPlayedAt ASC',
      'lastPlayed_desc' => 's.lastPlayedAt DESC',
      _ => 's.title ASC',
    };
    final sql = StringBuffer('SELECT s.id, s.filePath FROM songs s');
    if (where.isNotEmpty) {
      sql.write(' WHERE ${where.join(rule.match == 'any' ? ' OR ' : ' AND ')}');
    }
    sql.write(' ORDER BY $order');
    if (rule.limit != null && rule.order != 'random_daily') {
      sql.write(' LIMIT ?');
      args.add(rule.limit);
    }
    final rows = await database.rawQuery(sql.toString(), args);
    final excluded = await DBHelper.instance.getExcludedFolders();
    var ids = rows
        .where((r) {
          final path = r['filePath'] as String? ?? '';
          return path.isEmpty || !excluded.contains(folderOf(path));
        })
        .map((r) => (r['id'] as num).toInt())
        .toList();
    if (rule.order == 'random_daily') {
      final seed = DateTime.now().year * 10000 +
          DateTime.now().month * 100 +
          DateTime.now().day +
          rule.salt;
      ids = List<int>.of(ids)..shuffle(Random(seed));
      if (rule.limit != null && ids.length > rule.limit!) {
        ids = ids.sublist(0, rule.limit!);
      }
    }
    return ids;
  }

  Future<int> rebuild(int playlistId) async {
    final rows = await DBHelper.instance.getPlaylists();
    final row = rows.firstWhere(
      (p) => (p['id'] as num?)?.toInt() == playlistId,
      orElse: () => const <String, dynamic>{},
    );
    final rule = SmartRule.tryParse(row['rule'] as String?);
    if (rule == null) return 0;
    final ids = await evaluate(rule);
    await DBHelper.instance.replacePlaylistSongs(playlistId, ids);
    return ids.length;
  }

  Future<void> rebuildAll({bool playStatsOnly = false}) async {
    for (final row in await DBHelper.instance.getPlaylists()) {
      final id = (row['id'] as num?)?.toInt();
      final rule = SmartRule.tryParse(row['rule'] as String?);
      if (id == null || rule == null) continue;
      if (playStatsOnly && !rule.needsPlayStats) continue;
      await rebuild(id);
    }
  }

  Future<void> setRule(int playlistId, SmartRule? rule) async {
    await DBHelper.instance.setPlaylistRule(
        playlistId, rule?.serialize());
    await rebuild(playlistId);
  }
}
