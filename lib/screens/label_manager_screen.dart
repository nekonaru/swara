import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/v6_strings.dart';
import '../providers/library_provider.dart';
import '../services/db_helper.dart';

/// Local label tools. No song is removed here; only label names change.
class LabelManagerScreen extends StatefulWidget {
  const LabelManagerScreen({super.key});

  @override
  State<LabelManagerScreen> createState() => _LabelManagerScreenState();
}

class _LabelManagerScreenState extends State<LabelManagerScreen> {
  List<String> _labels = const [];

  Future<void> _load() async {
    _labels = await DBHelper.instance.getDistinctLabels();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _afterChange() async {
    await context.read<LibraryProvider>().loadFromDb();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(V6.manageLabels)),
      body: _labels.isEmpty
          ? Center(child: Text(V6.noItems))
          : ListView.builder(
              itemCount: _labels.length,
              itemBuilder: (context, i) {
                final label = _labels[i];
                return ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text(label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: V6.renameLabel,
                        onPressed: () async {
                          final controller = TextEditingController(text: label);
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(V6.renameLabel),
                              content: TextField(
                                controller: controller,
                                decoration: InputDecoration(
                                    labelText: V6.labelName),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(l.cancel),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(l.save),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          final next = controller.text.trim();
                          if (next.isEmpty || next == label) return;
                          await DBHelper.instance.renameLabel(label, next);
                          await _afterChange();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.merge_type),
                        tooltip: V6.mergeLabel,
                        onPressed: () async {
                          final targets = _labels
                              .where((item) => item != label)
                              .toList();
                          if (targets.isEmpty) return;
                          final target = await showDialog<String>(
                            context: context,
                            builder: (ctx) => SimpleDialog(
                              title: Text('${V6.mergeInto} $label'),
                              children: [
                                for (final item in targets)
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(ctx, item),
                                    child: Text(item),
                                  ),
                              ],
                            ),
                          );
                          if (target == null) return;
                          await DBHelper.instance.mergeLabels(label, target);
                          await _afterChange();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: V6.removeLabel,
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(V6.removeLabel),
                              content: Text(l.destructiveConfirmMessage(label)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(l.cancel),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(l.delete),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          await DBHelper.instance.deleteLabel(label);
                          await _afterChange();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
