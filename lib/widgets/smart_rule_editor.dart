import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';

import '../models/smart_rule.dart';

/// Small dialog that builds a [SmartRule]. No network, no schema writes.
Future<SmartRule?> showSmartRuleEditor(
    BuildContext context, SmartRule? initial) async {
  final rule = initial ?? const SmartRule();
  final match = ValueNotifier<String>(rule.match);
  final order = ValueNotifier<String>(rule.order);
  final limitController =
      TextEditingController(text: rule.limit?.toString() ?? '');
  final rows = <_CriterionRow>[
    for (final c in rule.criteria) _CriterionRow.from(c),
  ];

  final result = await showDialog<SmartRule>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.smartRuleTitle),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(AppLocalizations.of(ctx)!.smartRuleMatchAll),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: match.value,
                      items: [
                        DropdownMenuItem(
                            value: 'all',
                            child: Text(AppLocalizations.of(ctx)!.smartRuleMatchAll)),
                        DropdownMenuItem(
                            value: 'any',
                            child: Text(AppLocalizations.of(ctx)!.smartRuleMatchAny)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => match.value = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < rows.length; i++)
                  _CriterionTile(
                    row: rows[i],
                    onRemove: () => setState(() => rows.removeAt(i)),
                  ),
                TextButton.icon(
                  onPressed: () => setState(() => rows.add(_CriterionRow())),
                  icon: const Icon(Icons.add),
                  label: Text(AppLocalizations.of(ctx)!.smartRuleAdd),
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: limitController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(ctx)!.smartRuleLimit),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: order.value,
                      items: const [
                        DropdownMenuItem(value: 'title_asc', child: Text('Title A-Z')),
                        DropdownMenuItem(value: 'title_desc', child: Text('Title Z-A')),
                        DropdownMenuItem(value: 'added_desc', child: Text('Newest')),
                        DropdownMenuItem(value: 'lastPlayed_asc', child: Text('Least recent')),
                        DropdownMenuItem(value: 'lastPlayed_desc', child: Text('Most recent')),
                        DropdownMenuItem(value: 'random_daily', child: Text('Daily mix')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => order.value = v);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx)!.cancel)),
          FilledButton(
            onPressed: () {
              final limit = int.tryParse(limitController.text.trim());
              Navigator.pop(
                ctx,
                SmartRule(
                  match: match.value,
                  criteria: [
                    for (final row in rows)
                      if (row.isValid) row.toCriterion(),
                  ],
                  order: order.value,
                  limit: limit != null && limit > 0 ? limit : null,
                  salt: rule.salt,
                ),
              );
            },
            child: Text(AppLocalizations.of(ctx)!.save),
          ),
        ],
      ),
    ),
  );
  limitController.dispose();
  return result;
}

class _CriterionRow {
  SmartField field = SmartField.artist;
  SmartOp op = SmartOp.contains;
  String value = '';

  _CriterionRow();

  factory _CriterionRow.from(SmartCriterion c) => _CriterionRow()
    ..field = c.field
    ..op = c.op
    ..value = c.value?.toString() ?? '';

  bool get isValid {
    if (_needsValue.contains(op)) return value.trim().isNotEmpty;
    return true;
  }

  static const _needsValue = <SmartOp>{
    SmartOp.contains,
    SmartOp.equals,
    SmartOp.startsWith,
    SmartOp.notContains,
    SmartOp.beforeDays,
    SmartOp.afterDays,
    SmartOp.eq,
    SmartOp.neq,
    SmartOp.gt,
    SmartOp.gte,
    SmartOp.lt,
    SmartOp.lte,
  };

  SmartCriterion toCriterion() => SmartCriterion(
        field: field,
        op: op,
        value: _needsValue.contains(op)
            ? (field == SmartField.playCount ||
                    field == SmartField.duration ||
                    field == SmartField.lastPlayed ||
                    field == SmartField.addedAt
                ? int.tryParse(value.trim()) ?? 0
                : value.trim())
            : null,
      );
}

class _CriterionTile extends StatelessWidget {
  final _CriterionRow row;
  final VoidCallback onRemove;

  const _CriterionTile({required this.row, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: DropdownButton<SmartField>(
            value: row.field,
            isExpanded: true,
            items: [
              for (final f in SmartField.values)
                DropdownMenuItem(value: f, child: Text(_fieldLabel(l, f))),
            ],
            onChanged: (v) {
              if (v != null) row.field = v;
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<SmartOp>(
            value: row.op,
            isExpanded: true,
            items: [
              for (final op in SmartOp.values)
                DropdownMenuItem(value: op, child: Text(_opLabel(l, op))),
            ],
            onChanged: (v) {
              if (v != null) row.op = v;
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: TextFormField(
            initialValue: row.value,
            onChanged: (v) => row.value = v,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l.smartRuleRemove,
          onPressed: onRemove,
        ),
      ],
    );
  }

  String _fieldLabel(AppLocalizations l, SmartField f) => switch (f) {
        SmartField.title => l.smartFieldTitle,
        SmartField.artist => l.smartFieldArtist,
        SmartField.album => l.smartFieldAlbum,
        SmartField.genre => l.smartFieldGenre,
        SmartField.favorite => l.smartFieldFavorite,
        SmartField.playCount => l.smartFieldPlayCount,
        SmartField.lastPlayed => l.smartFieldLastPlayed,
        SmartField.addedAt => l.smartFieldAddedAt,
        SmartField.duration => l.smartFieldDuration,
      };

  String _opLabel(AppLocalizations l, SmartOp o) => switch (o) {
        SmartOp.contains => l.smartOpContains,
        SmartOp.equals => l.smartOpEquals,
        SmartOp.startsWith => l.smartOpStartsWith,
        SmartOp.notContains => l.smartOpNotContains,
        SmartOp.isTrue => l.smartOpIsTrue,
        SmartOp.isFalse => l.smartOpIsFalse,
        SmartOp.isNull => l.smartOpIsNull,
        SmartOp.isNotNull => l.smartOpIsNotNull,
        SmartOp.beforeDays => l.smartOpBeforeDays,
        SmartOp.afterDays => l.smartOpAfterDays,
        SmartOp.eq => l.smartOpEq,
        SmartOp.neq => l.smartOpNeq,
        SmartOp.gt => l.smartOpGt,
        SmartOp.gte => l.smartOpGte,
        SmartOp.lt => l.smartOpLt,
        SmartOp.lte => l.smartOpLte,
      };
}
