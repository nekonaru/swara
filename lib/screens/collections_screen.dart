import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/db_helper.dart';
import '../services/m3u_service.dart';
import '../services/playlist_art_service.dart';
import 'extra_screens.dart';
import 'duplicates_screen.dart';
import 'history_screen.dart';
import 'playlist_detail_screen.dart';
import '../widgets/mini_player.dart';
import '../widgets/sort_chip.dart';

// Reference card colors (matching the Nomad Music artwork)
const _cardColors = [
  Color(0xFF7B1A1A), // Favorites - dark red
  Color(0xFF6B5200), // Recently added - gold
  Color(0xFF1A3A6B), // Recently played - blue
  Color(0xFF1A5C30), // Most played - green
];

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  bool _sortAZ = true;

  // Names for the built-in automatic playlists.
  static const String _dailyMixName = 'Daily Mix';
  static const String _unplayedName = 'Unplayed';
  static const int _dailyMixLimit = 25;

  // One-shot guard so the auto playlists are synced once per screen visit
  // instead of on every rebuild. Deleting an auto playlist only removes
  // that row; it is recreated on the next visit or manual refresh.
  bool _autoSyncing = false;
  bool _autoSynced = false;
  // Library version the auto playlists were built from.
  int _autoSyncedVersion = -1;
  // Extra salt added to the date seed when the user taps refresh.
  int _dailySalt = 0;

  String _sortLabel(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return _sortAZ ? l.collectionsSortNameAsc : l.collectionsSortNameDesc;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<PlaylistProvider>().load());
  }

  Future<void> _createPlaylist() async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.collectionsNewPlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l.collectionsPlaylistNameHint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l.create)),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty && mounted) {
      final prov = context.read<PlaylistProvider>();
      await prov.create(name);
      if (!mounted) return;
      try {
        final found = prov.playlists.firstWhere(
          (p) => (p['name'] as String) == name,
        );
        _scheduleArtRefresh(prov, found['id'] as int);
      } catch (_) {
        // New row shows the fallback icon until art is available.
      }
    }
  }

  // Fire and forget collage rebuild after playlist content changes.
  // Never blocks the UI and never throws: failures keep the fallback icon.
  void _scheduleArtRefresh(PlaylistProvider prov, int playlistId) {
    Future(() async {
      try {
        final songs = await prov.songsIn(playlistId);
        await PlaylistArtService.buildPlaylistArt(playlistId, songs);
        if (mounted) setState(() {});
      } catch (_) {
        // Keep the fallback icon on any failure.
      }
    });
  }

  Future<void> _confirmDelete(
      BuildContext ctx, PlaylistProvider prov, int id, String name) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(l.collectionsDeletePlaylist),
        content: Text(l.collectionsDeleteConfirm(name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l.delete)),
        ],
      ),
    );
    if (ok == true) {
      await prov.delete(id);
      try {
        await PlaylistArtService.clearPlaylistArt(id);
      } catch (_) {
        // Cache cleanup is best effort only.
      }
    }
  }

  bool _isAutoPlaylist(String name) =>
      name == _dailyMixName || name == _unplayedName;

  // Folder label of a playlist row. Missing or blank means ungrouped.
  String _folderOf(Map<String, dynamic> p) {
    final raw = p['folder'] as String?;
    return (raw ?? '').trim();
  }

  // Dialog to move one user playlist into an existing or a new folder.
  // Returns after reloading the provider. Auto playlists never call this.
  Future<void> _movePlaylistToFolder(
      BuildContext ctx, PlaylistProvider prov, int id, String current) async {
    List<String> existing = [];
    try {
      existing = await DBHelper.instance.getPlaylistFolders();
    } catch (_) {
      existing = [];
    }
    if (!ctx.mounted) return;
    final controller = TextEditingController(text: current);
    final selected = await showDialog<String?>(
      context: ctx,
      builder: (c) {
        final folders = existing.where((f) => f != current).toList();
        return AlertDialog(
          title: Text(AppLocalizations.of(c)!.plFolderMoveTo),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText:
                        AppLocalizations.of(c)!.plFolderNewName,
                  ),
                ),
                const SizedBox(height: 8),
                if (current.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.remove_circle_outline),
                    title:
                        Text(AppLocalizations.of(c)!.plFolderRemove),
                    subtitle: Text(current),
                    onTap: () => Navigator.pop(c, ''),
                  ),
                // Bounded folder list so dozens of folders scroll
                // inside the dialog instead of overflowing it.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.of(c).size.height * 0.4,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in folders)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading:
                              const Icon(Icons.folder_outlined),
                          title: Text(f),
                          onTap: () => Navigator.pop(c, f),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(AppLocalizations.of(c)!.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, controller.text.trim()),
              child: Text(AppLocalizations.of(c)!.plFolderMove),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (selected == null || !ctx.mounted) return;
    await DBHelper.instance.setPlaylistFolder(id, selected);
    await prov.load();
  }

  // Rename a folder. Playlists stay in place, only the label changes.
  Future<void> _renameFolder(
      BuildContext ctx, PlaylistProvider prov, String folder) async {
    final controller = TextEditingController(text: folder);
    final next = await showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(AppLocalizations.of(c)!.plFolderRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: folder),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(c)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: Text(AppLocalizations.of(c)!.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next.isEmpty || next == folder || !ctx.mounted) return;
    await DBHelper.instance.renamePlaylistFolder(folder, next);
    await prov.load();
  }

  // Delete a folder label only. Playlists inside become ungrouped.
  Future<void> _deleteFolder(BuildContext ctx, PlaylistProvider prov,
      String folder, int count) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(AppLocalizations.of(c)!.plFolderDelete),
        content: Text(AppLocalizations.of(c)!
            .plFolderDeleteConfirm(folder, count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(AppLocalizations.of(c)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(c)!.delete),
          ),
        ],
      ),
    );
    if (ok != true || !ctx.mounted) return;
    await DBHelper.instance.renamePlaylistFolder(folder, '');
    await prov.load();
  }

  // Seed derived from the current calendar date so the mix stays stable
  // for the whole day. The manual refresh salt makes a new mix on demand.
  int _dailySeed() {
    final now = DateTime.now();
    final base = now.year * 10000 + now.month * 100 + now.day;
    return base + _dailySalt;
  }

  // Pick up to [_dailyMixLimit] random songs from the loaded library.
  List<int> _pickDailyMixIds(LibraryProvider lib) {
    final ids = lib.songs.map((s) => s.id).toList();
    ids.shuffle(Random(_dailySeed()));
    if (ids.length > _dailyMixLimit) {
      return ids.sublist(0, _dailyMixLimit);
    }
    return ids;
  }

  void _showAutoError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              AppLocalizations.of(context)!.autoPlaylistError(e.toString()))),
    );
  }

  // Create the playlist when missing, otherwise replace its content.
  // Uses only the existing PlaylistProvider API so no other file changes.
  Future<void> _syncOneAutoPlaylist(
      PlaylistProvider prov, String name, List<int> songIds) async {
    try {
      await prov.load();
      if (!mounted) return;
      Map<String, dynamic>? existing;
      for (final p in prov.playlists) {
        if ((p['name'] as String) == name) {
          existing = p;
          break;
        }
      }
      int playlistId;
      if (existing == null) {
        await prov.create(name);
        if (!mounted) return;
        final found = prov.playlists.firstWhere(
          (p) => (p['name'] as String) == name,
        );
        playlistId = found['id'] as int;
      } else {
        playlistId = existing['id'] as int;
        final current = await prov.songsIn(playlistId);
        for (final s in current) {
          await prov.removeSong(playlistId, s.id);
        }
      }
      for (final id in songIds) {
        try {
          await prov.addSong(playlistId, id);
        } catch (_) {
          // Ignore per-song duplicate errors, keep syncing the rest.
        }
      }
      await prov.load();
      // Refresh the collage after the content changed, without blocking.
      _scheduleArtRefresh(prov, playlistId);
    } catch (e) {
      _showAutoError(e);
    }
  }

  Future<void> _syncDailyMix(
      PlaylistProvider prov, LibraryProvider lib) async {
    await _syncOneAutoPlaylist(prov, _dailyMixName, _pickDailyMixIds(lib));
  }

  Future<void> _syncUnplayed(PlaylistProvider prov, LibraryProvider lib) async {
    try {
      final never = await DBHelper.instance.getNeverPlayedSongs();
      if (!mounted) return;
      final visible = lib.songs.map((s) => s.id).toSet();
      final ids = never
          .map((s) => s.id)
          .where((id) => visible.contains(id))
          .toList();
      await _syncOneAutoPlaylist(prov, _unplayedName, ids);
    } catch (e) {
      _showAutoError(e);
    }
  }

  // Runs once when the library is ready. Never duplicates: existing
  // playlists with the same name are updated in place.
  Future<void> _ensureAutoPlaylists(
      PlaylistProvider prov, LibraryProvider lib) async {
    if (_autoSyncing || lib.songs.isEmpty) return;
    // Key the auto playlist sync to the library version, not to a one time
    // flag. Hiding a folder or rescanning changes the version, and Daily Mix
    // or Unplayed would otherwise keep listing songs that are no longer
    // visible until the app was restarted.
    if (_autoSynced && _autoSyncedVersion == lib.songsVersion) return;
    _autoSyncedVersion = lib.songsVersion;
    _autoSyncing = true;
    await _syncDailyMix(prov, lib);
    if (!mounted) return;
    await _syncUnplayed(prov, lib);
    if (!mounted) return;
    setState(() {
      _autoSyncing = false;
      _autoSynced = true;
    });
  }

  Future<void> _reshuffleDailyMix(
      PlaylistProvider prov, LibraryProvider lib) async {
    setState(() {
      _dailySalt = Random().nextInt(1 << 30);
    });
    await _syncDailyMix(prov, lib);
  }

  // Import an .m3u/.m3u8 file as a new playlist. The playlist name
  // comes from the file name; on a duplicate name error (UNIQUE
  // constraint from the existing DB layer) a numeric suffix is added
  // and creation is retried until it succeeds.
  Future<void> _importM3u() async {
    try {
      final lib = context.read<LibraryProvider>();
      final prov = context.read<PlaylistProvider>();
      final picked = await M3uService.pickAndMatch(lib.songs);
      if (picked == null || !mounted) return;

      var base = picked.playlistName.trim();
      if (base.isEmpty) {
        base = AppLocalizations.of(context)!.m3uImportedDefault;
      }
      var name = base;
      var suffix = 2;
      var playlistId = -1;
      while (playlistId < 0) {
        try {
          await prov.create(name);
          if (!mounted) return;
          final found = prov.playlists.firstWhere(
            (p) => (p['name'] as String) == name,
          );
          playlistId = found['id'] as int;
        } catch (e) {
          // Retry with a suffix only on duplicate name errors.
          if (!e.toString().contains('UNIQUE')) rethrow;
          name = '$base ($suffix)';
          suffix++;
        }
      }

      var added = 0;
      // One transaction for the whole import instead of one write per song.
      try {
        added = await prov.addSongs(
          playlistId,
          picked.match.matched.map((s) => s.id).toList(),
        );
      } catch (_) {
        added = 0;
      }
      await prov.load();
      // Refresh the collage for the imported content, without blocking.
      _scheduleArtRefresh(prov, playlistId);
      if (!mounted) return;
      // Report every entry that could not be placed, including the ones
      // skipped because the file name was shared by several songs.
      final unresolved = picked.match.unresolved;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.m3uImportSummary(
              added,
              picked.match.matched.length,
              name,
              unresolved)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!
              .m3uImportFailed(e.toString())),
        ),
      );
    }
  }

  // Export one user playlist to an M3U file in Downloads.
  // Songs are loaded through the existing provider API, then built
  // and saved exactly like the detail screen flow. Shows the saved
  // path on success or the error on failure.
  Future<void> _exportM3uPlaylist(
      PlaylistProvider prov, int playlistId, String playlistName) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final songs = await prov.songsIn(playlistId);
      if (!mounted) return;
      if (songs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.m3uExportEmpty),
          ),
        );
        return;
      }
      final content = M3uService.buildM3uContent(songs);
      final file =
          await M3uService.saveM3uToDownloads(playlistName, content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.m3uExported(file.path)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.m3uExportFailed(e.toString())),
        ),
      );
    }
  }

  // Merge songs from another playlist into [targetId].
  // Only songs not already present are added (checked via songsIn),
  // so the target never gets duplicates. Shows a summary snackbar.
  Future<void> _mergePlaylist(
      BuildContext ctx, PlaylistProvider prov, int targetId, String targetName) async {
    try {
      await prov.load();
    } catch (_) {
      // Fall through and use the cached list on load failure.
    }
    if (!ctx.mounted) return;
    final others = prov.playlists.where((p) => (p['id'] as int) != targetId).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(ctx)!.mergeNoOthers),
        ),
      );
      return;
    }
    // Simple source picker dialog: list other playlists by name.
    final picked = await showDialog<Map<String, dynamic>>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(AppLocalizations.of(c)!.mergeFrom),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in others)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.queue_music),
                  title: Text((p['name'] as String?) ?? ''),
                  onTap: () => Navigator.pop(c, p),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(c)!.cancel),
          ),
        ],
      ),
    );
    if (picked == null || !ctx.mounted) return;
    final sourceId = picked['id'] as int;
    final sourceName = (picked['name'] as String?) ?? '';
    try {
      final current = await prov.songsIn(targetId);
      final source = await prov.songsIn(sourceId);
      if (!ctx.mounted) return;
      final existingIds = current.map((s) => s.id).toSet();
      // Only the missing songs go in, in one transaction. The insert
      // re-checks inside the transaction, so a duplicate cannot slip in.
      final toAdd = <int>[];
      for (final s in source) {
        if (existingIds.contains(s.id)) continue;
        existingIds.add(s.id);
        toAdd.add(s.id);
      }
      final skipped = source.length - toAdd.length;
      var added = 0;
      try {
        added = await prov.addSongs(targetId, toAdd);
      } catch (_) {
        // The insert is atomic, so a failure means nothing was added.
        added = 0;
      }
      await prov.load();
      _scheduleArtRefresh(prov, targetId);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(ctx)!.mergeSummary(
              added, sourceName, targetName, skipped)),
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(ctx)!
              .mergeFailed(e.toString())),
        ),
      );
    }
  }

  // Single playlist row. Shared by the auto list and every folder section
  // so behavior (tap, reshuffle, delete) stays identical everywhere.
  Widget _playlistTile(BuildContext context, PlaylistProvider playlists,
      LibraryProvider lib, Map<String, dynamic> p, int animIndex) {
    final l = AppLocalizations.of(context)!;
    final name = p['name'] as String;
    final isAuto = _isAutoPlaylist(name);
    final isDaily = name == _dailyMixName;
    return TweenAnimationBuilder<double>(
      key: ValueKey('pl_${p['id']}'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 160 + (animIndex % 8) * 25),
      curve: Curves.easeOut,
      builder: (ctx, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
            offset: Offset(0, (1 - v) * 6), child: child),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        leading: _PlaylistTileArt(
          playlistId: p['id'] as int,
          isAuto: isAuto,
        ),
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: isAuto
            ? Text(AppLocalizations.of(context)!.autoBadge,
                style: const TextStyle(fontSize: 12))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDaily)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: AppLocalizations.of(context)!.reshuffleDailyMix,
                onPressed: () => _reshuffleDailyMix(playlists, lib),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (action) {
                if (action == 'delete') {
                  // Deleting an auto playlist is safe:
                  // it only removes that row and the
                  // next sync recreates it fresh.
                  _confirmDelete(context, playlists, p['id'], name);
                } else if (action == 'reshuffle' && isDaily) {
                  _reshuffleDailyMix(playlists, lib);
                } else if (action == 'move_folder' && !isAuto) {
                  _movePlaylistToFolder(
                      context, playlists, p['id'] as int, _folderOf(p));
                } else if (action == 'export_m3u' && !isAuto) {
                  _exportM3uPlaylist(
                      playlists, p['id'] as int, name);
                } else if (action == 'merge' && !isAuto) {
                  _mergePlaylist(
                      context, playlists, p['id'] as int, name);
                }
              },
              itemBuilder: (_) => [
                if (isDaily)
                  PopupMenuItem(
                      value: 'reshuffle',
                      child: Text(
                          AppLocalizations.of(context)!.reshuffle)),
                if (!isAuto)
                  PopupMenuItem(
                      value: 'move_folder',
                      child: Text(AppLocalizations.of(context)!
                          .plFolderMoveTo)),
                if (!isAuto)
                  PopupMenuItem(
                      value: 'export_m3u',
                      child: Text(AppLocalizations.of(context)!
                          .m3uExportMenu)),
                if (!isAuto)
                  PopupMenuItem(
                      value: 'merge',
                      child: Text(AppLocalizations.of(context)!
                          .mergeMenu)),
                PopupMenuItem(value: 'delete', child: Text(l.delete)),
              ],
            ),
          ],
        ),
        onTap: () => _openPage(
          context,
          PlaylistDetailScreen(playlistId: p['id'], playlistName: name),
        ),
      ),
    );
  }

  // Header for one folder section. Long press renames the folder.
  // The popup menu offers rename and delete (ungroup only).
  Widget _folderHeader(BuildContext context, PlaylistProvider prov,
      String folder, int count) {
    return GestureDetector(
      onLongPress: () => _renameFolder(context, prov, folder),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(folder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Text('$count',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (action) {
                if (action == 'rename') {
                  _renameFolder(context, prov, folder);
                } else if (action == 'delete') {
                  _deleteFolder(context, prov, folder, count);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'rename',
                    child: Text(AppLocalizations.of(context)!
                        .plFolderRename)),
                PopupMenuItem(
                    value: 'delete',
                    child: Text(AppLocalizations.of(context)!
                        .plFolderDelete)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, anim, __) => page,
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Consumer2<PlaylistProvider, LibraryProvider>(
      builder: (context, playlists, lib, _) {
        // Sync the auto playlists whenever the library changed. Post frame
        // avoids calling provider methods during build.
        if (!_autoSyncing &&
            lib.songs.isNotEmpty &&
            (!_autoSynced || _autoSyncedVersion != lib.songsVersion)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _ensureAutoPlaylists(playlists, lib);
          });
        }
        final all = List<Map<String, dynamic>>.from(playlists.playlists);
        // Auto playlists first so they stand out, then user playlists.
        final auto = all
            .where((p) => _isAutoPlaylist(p['name'] as String))
            .toList();
        final user = all
            .where((p) => !_isAutoPlaylist(p['name'] as String))
            .toList();
        void sortByName(List<Map<String, dynamic>> list) {
          if (_sortAZ) {
            list.sort((a, b) => (a['name'] as String)
                .toLowerCase()
                .compareTo((b['name'] as String).toLowerCase()));
          } else {
            list.sort((a, b) => (b['name'] as String)
                .toLowerCase()
                .compareTo((a['name'] as String).toLowerCase()));
          }
        }

        sortByName(auto);
        sortByName(user);
        final pl = [...auto, ...user];
        // Group user playlists by folder. Auto playlists stay on top
        // and are never grouped, preserving the old behavior.
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        final List<Map<String, dynamic>> ungrouped = [];
        for (final p in user) {
          final folder = _folderOf(p);
          if (folder.isEmpty) {
            ungrouped.add(p);
          } else {
            grouped.putIfAbsent(folder, () => []).add(p);
          }
        }
        final folders = grouped.keys.toList();
        if (_sortAZ) {
          folders.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        } else {
          folders.sort((a, b) => b.toLowerCase().compareTo(a.toLowerCase()));
        }

        return Stack(
          children: [
            CustomScrollView(
              slivers: [
                // ── Quick-access cards (Favorites, Recently added, Recently played, Most played) ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.6,
                      children: [
                        _QuickCard(
                          title: l.collectionsFavorites,
                          subtitle: l.librarySongCount(lib.favorites.length),
                          icon: Icons.favorite,
                          bgColor: _cardColors[0],
                          onTap: () => _openPage(context, const _FavSheet()),
                        ),
                        _QuickCard(
                          title: l.collectionsRecentlyAdded,
                          subtitle: '',
                          icon: Icons.add_box_outlined,
                          bgColor: _cardColors[1],
                          onTap: () =>
                              _openPage(context, const _RecentlySheet()),
                        ),
                        _QuickCard(
                          title: l.collectionsRecentlyPlayed,
                          subtitle: '',
                          icon: Icons.history_outlined,
                          bgColor: _cardColors[2],
                          onTap: () =>
                              _openPage(context, const _HistorySheet()),
                        ),
                        _QuickCard(
                          title: l.collectionsMostPlayed,
                          subtitle: '',
                          icon: Icons.trending_up_outlined,
                          bgColor: _cardColors[3],
                          onTap: () =>
                              _openPage(context, const _MostPlayedSheet()),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Duplicate finder entry ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.copy_outlined),
                        title: Text(AppLocalizations.of(context)!
                            .dupFinderTitle),
                        subtitle: Text(
                          AppLocalizations.of(context)!.dupFinderCount(
                              countDuplicateGroups(lib.songs)),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openPage(
                            context, const DuplicatesScreen()),
                      ),
                    ),
                  ),
                ),

                // ── Sort bar + count ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      children: [
                        // Shared ripple chip, same label as before.
                        SortChip(
                          label: _sortLabel(context),
                          onTap: () => setState(() {
                            _sortAZ = !_sortAZ;
                          }),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _importM3u,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.upload_file_outlined,
                                    size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text(
                                    AppLocalizations.of(context)!
                                        .m3uImportButton,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: cs.primary)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l.collectionsPlaylistCount(pl.length),
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                ),

                // Playlist sections: auto on top, then one per folder.
                if (pl.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.queue_music_outlined,
                              size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(l.collectionsNoPlaylists,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  )
                else ...[
                  // Auto playlists stay flat on top, never grouped.
                  if (auto.isNotEmpty)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _playlistTile(
                            context, playlists, lib, auto[i], i),
                        childCount: auto.length,
                      ),
                    ),
                  // One section per folder, in the current sort order.
                  for (final folder in folders) ...[
                    SliverToBoxAdapter(
                      child: _folderHeader(context, playlists, folder,
                          grouped[folder]!.length),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _playlistTile(context, playlists,
                            lib, grouped[folder]![i], i),
                        childCount: grouped[folder]!.length,
                      ),
                    ),
                  ],
                  if (ungrouped.isNotEmpty) ...[
                    // Show the Ungrouped header only when folders exist,
                    // so the old flat look is kept when unused.
                    if (folders.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                    AppLocalizations.of(context)!
                                        .plFolderUngrouped,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _playlistTile(context, playlists,
                            lib, ungrouped[i], auto.length + i),
                        childCount: ungrouped.length,
                      ),
                    ),
                  ],
                ],

                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
              ],
            ),

            // Add-playlist FAB
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'fab_new_playlist',
                onPressed: _createPlaylist,
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Playlist tile art: cached collage file with icon fallback.
// ─────────────────────────────────────────────────────────────

// Small square tile showing the generated collage when cached,
// otherwise the same icon style the list used before.
class _PlaylistTileArt extends StatelessWidget {
  final int playlistId;
  final bool isAuto;

  const _PlaylistTileArt({required this.playlistId, required this.isAuto});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isAuto ? cs.secondaryContainer : cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isAuto ? Icons.auto_awesome_outlined : Icons.queue_music,
        color: isAuto ? cs.onSecondaryContainer : cs.onPrimaryContainer,
        size: 22,
      ),
    );
    // A fresh future per build keeps the code simple: playlist rows are
    // few and the lookup is a cheap file stat. Parent rebuilds (for
    // example after _scheduleArtRefresh calls setState) pick up new art.
    return FutureBuilder<File?>(
      future: PlaylistArtService.existingArt(playlistId),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            cacheWidth: 88,
            errorBuilder: (_, __, ___) => fallback,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Quick card widget
// ─────────────────────────────────────────────────────────────

class _QuickCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color bgColor;
  final VoidCallback onTap;

  const _QuickCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Wrapper screens (opened from the quick cards) - with AppBar + MiniPlayer
// ─────────────────────────────────────────────────────────────

class _FavSheet extends StatelessWidget {
  const _FavSheet();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.collectionsFavorites)),
    body: const FavoritesScreen(),
    bottomNavigationBar: const MiniPlayer(),
  );
}

class _RecentlySheet extends StatelessWidget {
  const _RecentlySheet();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        title:
            Text(AppLocalizations.of(context)!.collectionsRecentlyAddedTitle)),
    body: const RecentlyAddedScreen(),
    bottomNavigationBar: const MiniPlayer(),
  );
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        title:
            Text(AppLocalizations.of(context)!.collectionsRecentlyPlayedTitle)),
    body: const HistoryScreen(),
    bottomNavigationBar: const MiniPlayer(),
  );
}

class _MostPlayedSheet extends StatelessWidget {
  const _MostPlayedSheet();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.collectionsMostPlayedTitle)),
    body: const MostPlayedScreen(),
    bottomNavigationBar: const MiniPlayer(),
  );
}
