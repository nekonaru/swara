import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';

// Pure helper: normalize one part (title or artist) for duplicate grouping.
// Lowercases, trims, removes common punctuation, collapses whitespace.
String normalizeDuplicatePart(String input) {
  var s = input.toLowerCase().trim();
  // Remove common punctuation so "Hello!" matches "hello".
  s = s.replaceAll(RegExp(r"[.,;:!?()\[\]{}<>_/\-\\|@#\$%^&*~`+=]"), '');
  s = s.replaceAll("'", '');
  s = s.replaceAll('"', '');
  // Collapse repeated whitespace into a single space.
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

// Pure helper: normalized grouping key "title | artist | album | duration".
//
// Album and a coarse duration bucket are part of the key on purpose. With
// only title and artist, a studio track and a live or remix version of the
// same song land in one group, and the bulk delete then removes a completely
// different recording together with its playlist entries and history.
String duplicateGroupKey(String title, String artist,
    {String? album, int durationMs = 0}) {
  // Two seconds of slack absorbs re-encodes and rounding, while still
  // separating versions whose length differs noticeably.
  final bucket = (durationMs / 2000).round();
  return '${normalizeDuplicatePart(title)} | ${normalizeDuplicatePart(artist)}'
      ' | ${normalizeDuplicatePart(album ?? '')} | $bucket';
}

// Pure helper: grouping key for one song.
String duplicateGroupKeyForSong(Song song) {
  return duplicateGroupKey(
    song.title,
    song.artist,
    album: song.album,
    durationMs: song.durationMs,
  );
}

/// Whether [candidate] really is another copy of [keeper] and not a different
/// recording that happens to share a title. Guard for every delete path.
bool isSameRecording(Song candidate, Song keeper) {
  if (normalizeDuplicatePart(candidate.album) !=
      normalizeDuplicatePart(keeper.album)) {
    return false;
  }
  final delta = (candidate.durationMs - keeper.durationMs).abs();
  // 2.5 seconds of slack; different versions are far beyond that.
  return delta < 2500;
}

// Pure helper: group songs by normalized key, keep only groups of 2 or more.
// Groups are sorted by key so the output order is stable.
Map<String, List<Song>> findDuplicateGroups(List<Song> songs) {
  final Map<String, List<Song>> all = {};
  for (final song in songs) {
    final key = duplicateGroupKeyForSong(song);
    (all[key] ??= []).add(song);
  }
  final Map<String, List<Song>> dupes = {};
  for (final entry in all.entries) {
    if (entry.value.length >= 2) {
      // Sort members by id so the kept song is deterministic.
      final members = List<Song>.of(entry.value)
        ..sort((a, b) => a.id.compareTo(b.id));
      dupes[entry.key] = members;
    }
  }
  // Return keys in sorted order for a stable list.
  final sortedKeys = dupes.keys.toList()..sort();
  return {for (final k in sortedKeys) k: dupes[k]!};
}

// Pure helper: number of duplicate groups in a song list.
int countDuplicateGroups(List<Song> songs) {
  return findDuplicateGroups(songs).length;
}

// Screen listing duplicate songs grouped by normalized "title | artist".
class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  // Ids of songs checked by the user for the manual bulk delete.
  final Set<int> _selectedIds = {};
  // Group keys currently expanded. Empty means all collapsed.
  final Set<String> _expandedKeys = {};
  bool _working = false;

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // Select every song except the first one in each group, so one remains.
  void _selectExtras(Map<String, List<Song>> groups) {
    setState(() {
      _selectedIds.clear();
      for (final members in groups.values) {
        for (var i = 1; i < members.length; i++) {
          _selectedIds.add(members[i].id);
        }
      }
    });
  }

  Future<void> _playSong(List<Song> queue, int index) async {
    try {
      await PlayerService.instance.setQueueAndPlay(queue, index);
      if (!mounted) return;
      final err = PlayerService.instance.lastError;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .dupPlayFailed(err.toString()))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .dupPlayFailed(e.toString()))),
      );
    }
  }

  // Delete the checked songs. When a whole group is checked, the first
  // song of that group is kept so one copy always remains.
  Future<void> _deleteSelected(Map<String, List<Song>> groups) async {
    if (_selectedIds.isEmpty) return;
    // Build the final delete list, skipping the first song of any group
    // where every member is checked.
    final List<Song> toDelete = [];
    for (final members in groups.values) {
      final checked =
          members.where((s) => _selectedIds.contains(s.id)).toList();
      if (checked.isEmpty) continue;
      if (checked.length >= members.length) {
        // Keep the first song of the group.
        toDelete.addAll(checked.where((s) => s.id != members.first.id));
      } else {
        toDelete.addAll(checked);
      }
    }
    if (toDelete.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dupDeleteTitle),
        content: Text(l10n.dupDeleteMessage(toDelete.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _working = true);
    var removed = 0;
    try {
      final lib = context.read<LibraryProvider>();
      // One batch: deleting row by row rebuilt the row index and the A-Z map
      // for every single removal.
      await lib.deleteSongs(toDelete);
      removed = toDelete.length;
      if (!mounted) return;
      setState(() {
        _selectedIds.removeWhere((id) => toDelete.any((s) => s.id == id));
        _working = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .dupRemoved(removed, toDelete.length))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .dupDeleteFailed(e.toString()))),
      );
    }
  }

  // Bulk action: keep the first song of each group, delete the rest.
  Future<void> _removeAllDuplicates(Map<String, List<Song>> groups) async {
    final List<Song> extras = [];
    for (final members in groups.values) {
      if (members.length > 1) {
        extras.addAll(members.skip(1));
      }
    }
    if (extras.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dupRemoveAllTitle),
        content: Text(
            l10n.dupRemoveAllMessage(extras.length, groups.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _working = true);
    var removed = 0;
    try {
      final lib = context.read<LibraryProvider>();
      // One batch instead of one notify (and one map rebuild) per row.
      await lib.deleteSongs(extras);
      removed = extras.length;
      if (!mounted) return;
      setState(() {
        _selectedIds.removeWhere((id) => extras.any((s) => s.id == id));
        _working = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .dupRemovedAll(removed, groups.length))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .dupDeleteFailed(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dupTitle)),
      bottomNavigationBar: const MiniPlayer(),
      body: Consumer<LibraryProvider>(
        builder: (context, lib, _) {
          final groups = findDuplicateGroups(lib.songs);
          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copy_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text(
                    l10n.dupEmpty,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }
          final keys = groups.keys.toList();
          final totalExtras =
              groups.values.fold<int>(0, (sum, m) => sum + m.length - 1);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.dupSummary(groups.length, totalExtras),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                    TextButton(
                      onPressed: _working ? null : () => _selectExtras(groups),
                      child: Text(l10n.dupSelectExtras),
                    ),
                  ],
                ),
              ),
              if (_selectedIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.dupSelected(_selectedIds.length),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _working ? null : () => _deleteSelected(groups),
                        icon: _working
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_outline, size: 18),
                        label: Text(l10n.dupDeleteSelected),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: keys.length,
                  itemBuilder: (context, i) {
                    final key = keys[i];
                    final members = groups[key]!;
                    final first = members.first;
                    final expanded = _expandedKeys.contains(key);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.copy_outlined),
                            // Show the display title and artist from the first member.
                            title: Text(
                              first.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              l10n.dupCopies(first.artist, members.length),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(label: Text(l10n.dupKeepOne)),
                                Icon(expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more),
                              ],
                            ),
                            onTap: () => setState(() {
                              if (expanded) {
                                _expandedKeys.remove(key);
                              } else {
                                _expandedKeys.add(key);
                              }
                            }),
                          ),
                          if (expanded)
                            ...members.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final song = entry.value;
                              final checked =
                                  _selectedIds.contains(song.id);
                              final isKept = idx == 0;
                              return ListTile(
                                contentPadding: const EdgeInsets.fromLTRB(
                                    8, 0, 8, 0),
                                leading: Checkbox(
                                  value: checked,
                                  onChanged: (_) => _toggleSelect(song.id),
                                ),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${song.artist} - ${song.filePath}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isKept)
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          l10n.dupKept,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.green),
                                        ),
                                      ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.play_arrow, size: 22),
                                      tooltip: l10n.dupPlay,
                                      onPressed: () =>
                                          _playSong(members, idx),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _working
                          ? null
                          : () => _removeAllDuplicates(groups),
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: Text(l10n.dupRemoveAll),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
