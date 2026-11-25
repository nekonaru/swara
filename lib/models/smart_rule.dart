import 'dart:convert';

enum SmartField {
  title,
  artist,
  album,
  genre,
  favorite,
  playCount,
  lastPlayed,
  addedAt,
  duration,
}

enum SmartOp {
  contains,
  equals,
  startsWith,
  notContains,
  isTrue,
  isFalse,
  isNull,
  isNotNull,
  eq,
  neq,
  gt,
  gte,
  lt,
  lte,
  beforeDays,
  afterDays,
}

class SmartCriterion {
  final SmartField field;
  final SmartOp op;
  final Object? value;

  const SmartCriterion({
    required this.field,
    required this.op,
    this.value,
  });

  Map<String, dynamic> toJson() => {
        'field': field.name,
        'op': op.name,
        'value': value,
      };

  factory SmartCriterion.fromJson(Map<String, dynamic> json) {
    return SmartCriterion(
      field: SmartField.values.byName(json['field'] as String),
      op: SmartOp.values.byName(json['op'] as String),
      value: json['value'],
    );
  }
}

class SmartRule {
  final int schema;
  final String match;
  final List<SmartCriterion> criteria;
  final String order;
  final int? limit;
  final int salt;

  const SmartRule({
    this.schema = 1,
    this.match = 'all',
    this.criteria = const <SmartCriterion>[],
    this.order = 'title_asc',
    this.limit,
    this.salt = 0,
  });

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'match': match,
        'criteria': [for (final c in criteria) c.toJson()],
        'order': order,
        'limit': limit,
        'salt': salt,
      };

  String serialize() => jsonEncode(toJson());

  static SmartRule? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['schema'] != 1) return null;
      final match = map['match'] as String?;
      if (match != 'all' && match != 'any') return null;
      const orders = <String>{
        'title_asc', 'title_desc', 'added_desc', 'lastPlayed_asc',
        'lastPlayed_desc', 'random_daily',
      };
      final order = map['order'] as String? ?? 'title_asc';
      if (!orders.contains(order)) return null;
      final criteria = <SmartCriterion>[];
      for (final item in (map['criteria'] as List? ?? const [])) {
        if (item is! Map<String, dynamic>) return null;
        criteria.add(SmartCriterion.fromJson(item));
      }
      final rawLimit = map['limit'];
      final limit = rawLimit is num ? rawLimit.toInt() : null;
      final salt = (map['salt'] as num?)?.toInt() ?? 0;
      return SmartRule(
        match: match ?? 'all',
        criteria: criteria,
        order: order,
        limit: limit != null && limit > 0 ? limit : null,
        salt: salt,
      );
    } catch (_) {
      return null;
    }
  }

  bool get needsPlayStats => criteria.any((c) =>
      c.field == SmartField.playCount || c.field == SmartField.lastPlayed);
}
