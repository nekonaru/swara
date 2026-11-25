import 'package:flutter/material.dart';
import '../utils/row_layout.dart';
import 'package:provider/provider.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import '../providers/playlist_provider.dart';
import '../services/player_service.dart';

// Queue rows keep the effective text scale; the list extent grows with it.
Widget _clampQueueRowText(BuildContext context, Widget child) => child;

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});
  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final _player = PlayerService.instance;
  final ScrollController _scrollController = ScrollController();
  static const double _itemHeight = 68;
  bool _scrolledOnce = false;

  @override
  void initState() {
    super.initState();
    // Initial scroll once after the first frame; later queue changes
    // are observed through a listener - no side effects in build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentIfNeeded());
    _player.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    _player.removeListener(_onQueueChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueueChanged() => _scrollToCurrentIfNeeded();

  void _scrollToCurrentIfNeeded() {
    if (_scrolledOnce) return;
    if (_player.queue.isEmpty) return;
    _scrolledOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final currentIndex = _player.currentIndex;
      // Show the currently playing song near the top of the screen (not flush with the very top)
      final rowHeight = scaledRowHeight(context, _itemHeight);
      final target = (currentIndex * rowHeight - rowHeight).clamp(0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target.toDouble(),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // Default name for the "save queue as playlist" dialog.
  // Includes hour and minute so saving twice in one day does not collide.
  String _defaultQueuePlaylistName() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return 'Queue ${now.year}-$mm-$dd $hh-$min';
  }

  // Remove one queue entry by stable slot id. Resolves the live position
  // first; a null result means the entry is already gone, so ignore it.
  void _removeSlot(int slotId) {
    final int? pos = _player.queuePosForSlot(slotId);
    if (pos == null) return;
    _player.removeFromQueue(pos);
  }

  // Save the current queue (in playback order) as a new playlist.
  // Uses only the existing PlaylistProvider API. Shows success or
  // failure feedback via snackbar.
  Future<void> _saveQueueAsPlaylist() async {
    final queue = _player.queue;
    if (queue.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final controller =
        TextEditingController(text: _defaultQueuePlaylistName());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.queueSaveTooltip),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.queueSaveHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (name == null || name.isEmpty) return;

    final prov = context.read<PlaylistProvider>();
    // QueueScreen does not load playlists on init, so refresh before the
    // name-collision check; otherwise an existing name throws UNIQUE.
    try {
      await prov.load();
    } catch (_) {
      // Keep the cached list if the reload failed; creation still reports
      // a clear error through the snackbar below.
    }
    if (!mounted) return;
    // Resolve a unique name up front by checking existing playlist names,
    // same "(2)" suffix pattern as collections. This never depends on
    // parsing a database error string.
    var base = name.trim();
    if (base.isEmpty) base = _defaultQueuePlaylistName();
    final existingNames = <String>{
      for (final p in prov.playlists) (p['name'] as String),
    };
    var finalName = base;
    var suffix = 2;
    while (existingNames.contains(finalName)) {
      finalName = '$base ($suffix)';
      suffix++;
    }

    try {
      await prov.create(finalName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 2),
          content: Text(AppLocalizations.of(context)!
              .queueSaveFailed(e.toString())),
        ),
      );
      return;
    }
    if (!mounted) return;
    // Safe lookup: a missing entry shows a clear error instead of
    // throwing a StateError from firstWhere without orElse.
    Map<String, dynamic>? found;
    for (final p in prov.playlists) {
      if ((p['name'] as String) == finalName) {
        found = p;
        break;
      }
    }
    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 2),
          content: Text(AppLocalizations.of(context)!.queueNotFound),
        ),
      );
      return;
    }
    final playlistId = found['id'] as int;
    try {
      // One batched insert: the per-song path re-read the whole playlist
      // and decompressed its lyrics for every single song (O(n^2)).
      final added = await prov.addSongs(
        playlistId,
        queue.map((s) => s.id).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 2),
          content: Text(AppLocalizations.of(context)!
              .queueSaved(added, queue.length, finalName)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 2),
          content: Text(AppLocalizations.of(context)!
              .queueSaveFailed(e.toString())),
        ),
      );
    }
  }

  // Clear every song after the current one, keeping the current song.
  // Removes from the back so live positions stay valid while deleting.
  // Uses only the existing removeFromQueue API.
  Future<void> _clearUpNext() async {
    // A crossfade may already have loaded the next song into the standby
    // player. That song stays: it is already audible, so it must remain in
    // the queue. Everything after it goes.
    final pending = _player.pendingCrossfadePosition;
    final keepThrough = pending != null && pending > _player.currentIndex
        ? pending
        : _player.currentIndex;
    // Materialize the queue once. The getter rebuilds it from the play
    // order on every call, which was O(n^2) when clearing a large tail.
    final queueLength = _player.queue.length;
    final count = queueLength - keepThrough - 1;
    if (count <= 0) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.queueClearTitle),
        content: Text(l10n.queueClearMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.queueClearAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // The crossfade may have flipped while the dialog was open, so the
    // boundary is recomputed instead of trusted.
    final pendingNow = _player.pendingCrossfadePosition;
    final last = pendingNow != null && pendingNow > _player.currentIndex
        ? pendingNow
        : _player.currentIndex;
    final removed = await _player.removeQueueTail(last);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(seconds: 2),
        content: Text(l10n.queueCleared(removed)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Provide the singleton locally so this screen is self-sufficient and
    // Selector never depends on the ancestor setup.
    return ChangeNotifierProvider.value(
      value: _player,
      child: Selector<PlayerService, (int, int)>(
      // Rebuild only when the track index or the queue itself changes;
      // the rest (volume drag, speed throttle, favourite toggle) stays cheap.
      selector: (_, ps) => (ps.currentIndex, ps.queueVersion),
      builder: (context, _, __) {
        final queue = _player.queue;
        final slotIds = _player.queueSlotIds;
        final currentIndex = _player.currentIndex;

        return Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.of(context)!.queueTitle),
            actions: [
              IconButton(
                tooltip:
                    AppLocalizations.of(context)!.queueSaveTooltip,
                icon: const Icon(Icons.playlist_add),
                onPressed: queue.isEmpty ? null : _saveQueueAsPlaylist,
              ),
              IconButton(
                tooltip:
                    AppLocalizations.of(context)!.queueClearTooltip,
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: (queue.isEmpty ||
                        currentIndex >= queue.length - 1)
                    ? null
                    : _clearUpNext,
              ),
            ],
          ),
          body: queue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.queue_music_outlined,
                          size: 64, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(AppLocalizations.of(context)!.queueEmpty,
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.drag_handle, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(AppLocalizations.of(context)!.queueReorderHint,
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        scrollController: _scrollController,
                        itemCount: queue.length,
                        // The list must know its extent without laying out
                        // rows; without this, jumping to the playing row in a
                        // huge queue builds it in one frame and ANRs.
                        itemExtent: scaledRowHeight(context, _itemHeight),
                        onReorderItem: (oldIndex, newIndex) => _player.reorderQueue(oldIndex, newIndex),
                        itemBuilder: (context, i) {
                          final song = queue[i];
                          final slotId = slotIds[i]; // Stable ID - unchanged even when the list refreshes
                          final isPlaying = i == currentIndex;
                          return SizedBox(
                            key: ValueKey('queue_slot_$slotId'),
                            height: scaledRowHeight(context, _itemHeight),
                            child: Dismissible(
                              key: ValueKey('queue_dismiss_slot_$slotId'),
                              direction: isPlaying ? DismissDirection.none : DismissDirection.endToStart,
                              onDismissed: (_) => _removeSlot(slotId),
                              background: Container(
                                color: Theme.of(context).colorScheme.error,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              child: Container(
                                color: isPlaying
                                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
                                    : null,
                                child: _clampQueueRowText(context, ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16),
                                  leading: isPlaying
                                      ? Icon(Icons.equalizer, color: Theme.of(context).colorScheme.primary)
                                      : Text('${i + 1}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal)),
                                  subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isPlaying)
                                        IconButton(
                                          constraints:
                                              const BoxConstraints(
                                                  minWidth: 48,
                                                  minHeight: 48),
                                          icon: const Icon(Icons.close, size: 20),
                                          tooltip: AppLocalizations.of(context)!.remove,
                                          onPressed: () => _removeSlot(slotId),
                                        ),
                                      Icon(Icons.drag_handle, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ],
                                  ),
                                  onTap: () => _player.playAtQueueIndex(i),
                                )),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
      ),
    );
  }
}
