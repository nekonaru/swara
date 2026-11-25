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

  /// Built-in rules. The name is only a display default: renamed built-ins
  /// are recognized by isAuto with no rule, so their rule survives a rename.
  static const builtInSeeds = <(String name, String rule)>[
    (
      'Unplayed',
      '{"schema":1,"match":"all","criteria":[{"field":"lastPlayed","op":"isNull","value":null}],"order":"title_asc","limit":null,"salt":0}',
    ),
    (
      'Forgotten Favorites',
      '{"schema":1,"match":"all","criteria":[{"field":"favorite","op":"isTrue","value":null},{"field":"lastPlayed","op":"beforeDays","value":90}],"order":"lastPlayed_asc","limit":null,"salt":0}',
    ),
    (
      'Daily Mix',
      '{"schema":1,"match":"all","criteria":[],"order":"random_daily","limit":25,"salt":0}',
    ),
  ];

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
          // Never-played favorites count as forgotten; unknown added dates
          // must not be treated as old.
          if (c.field == SmartField.lastPlayed) {
            return '($expr IS NULL OR julianday($expr) < '
                "julianday('now', '-' || ? || ' days'))";
          }
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
    sql.write(' ORDER BY $order LIMIT ? OFFSET ?');
    final excluded = await DBHelper.instance.getExcludedFolders();
    final need = rule.limit;
    final chunkSize = need == null
        ? 5000
        : (need * 4 + 50).clamp(50, 1000).toInt();
    var ids = <int>[];
    var offset = 0;
    while (true) {
      final pageArgs = <Object?>[...args, chunkSize, offset];
      final rows = await database.rawQuery(sql.toString(), pageArgs);
      for (final row in rows) {
        final path = row['filePath'] as String? ?? '';
        if (path.isEmpty || isHiddenPath(path, excluded)) continue;
        ids.add((row['id'] as num).toInt());
        if (need != null && ids.length >= need && rule.order != 'random_daily') {
          break;
        }
      }
      if (rows.length < chunkSize ||
          (need != null &&
              ids.length >= need &&
              rule.order != 'random_daily')) {
        break;
      }
      offset += chunkSize;
    }
    if (rule.limit != null &&
        rule.order != 'random_daily' &&
        ids.length > rule.limit!) {
      ids = ids.sublist(0, rule.limit!);
    }
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
    return _rebuildWithRule(playlistId, rule);
  }

  Future<int> _rebuildWithRule(int playlistId, SmartRule rule) async {
    final ids = await evaluate(rule);
    await DBHelper.instance.replacePlaylistSongs(playlistId, ids);
    return ids.length;
  }

  /// Make sure the three built-ins exist, including on a fresh database and
  /// after a user deletes one. A renamed built-in is recognized by isAuto with
  /// no rule, so its new rule survives the rename.
  Future<List<int>> ensureBuiltIns() async {
    final rows = await DBHelper.instance.getPlaylists();
    final unassigned = rows
        .where((p) =>
            (p['isAuto'] as num?) == 1 &&
            (p['rule'] as String?)?.isNotEmpty != true)
        .toList();
    final seeded = <int>[];
    var cursor = 0;
    for (final (name, ruleText) in builtInSeeds) {
      final exact = rows.where((p) => (p['rule'] as String?) == ruleText);
      if (exact.isNotEmpty) continue;
      final named = rows
          .where((p) => (p['name'] as String?) == name)
          .toList();
      if (named.isNotEmpty) {
        // A pre-v4.12 or restored row with the built-in name but no rule is
        // a repair target, not a reason to skip seeding.
        final id = (named.first['id'] as num).toInt();
        await DBHelper.instance.setPlaylistRule(id, ruleText);
        seeded.add(id);
        continue;
      }
      if (cursor < unassigned.length) {
        final id = (unassigned[cursor]['id'] as num).toInt();
        await DBHelper.instance.setPlaylistRule(id, ruleText);
        seeded.add(id);
        cursor++;
      } else {
        final id = await DBHelper.instance.createPlaylist(name,
            isAuto: true, rule: ruleText);
        seeded.add(id);
      }
    }
    return seeded;
  }

  Future<void> rebuildAll({bool playStatsOnly = false}) async {
    final seeded = playStatsOnly
        ? const <int>[]
        : await ensureBuiltIns();
    final rows = await DBHelper.instance.getPlaylists();
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      final rule = SmartRule.tryParse(row['rule'] as String?);
      if (id == null || rule == null) continue;
      if (playStatsOnly && !rule.needsPlayStats && !seeded.contains(id)) {
        continue;
      }
      await _rebuildWithRule(id, rule);
    }
  }

  Future<void> setRule(int playlistId, SmartRule? rule) async {
    await DBHelper.instance.setPlaylistRule(
        playlistId, rule?.serialize());
    await rebuild(playlistId);
  }
}
