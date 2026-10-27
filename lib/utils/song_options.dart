import 'dart:io';

import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
// Requires adding share_plus to pubspec dependencies to compile.
// Standard API used below: Share.shareXFiles([XFile(path)], text: ...)
// with Share.share(text) as fallback. Verify against the installed
// share_plus version if the API differs.
import 'package:share_plus/share_plus.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/db_helper.dart';
import '../services/player_service.dart';
import '../screens/edit_metadata_screen.dart';

/// Shared song options menu (bottom sheet) used on all screens.
///
/// - From All Songs/Folders/History/Queue: [showFullDelete] true (default) -
///   "Delete from Library" removes from ALL places (including favorites and playlists),
///   but the original file on the phone stays safe and reappears when folders are rescanned.
/// - From Favorites: pass [showFullDelete]=false - the delete option is just
///   "Remove from Favorites" (a plain toggle), the song stays in All Songs/Folders/other playlists.
/// - From a specific playlist: pass [playlistId] - a "Remove from This Playlist"
///   option appears which only removes the song from that playlist and touches nothing else.
Future<void> showSongOptions(
  BuildContext context,
  Song song, {
  bool showFullDelete = true,
  int? playlistId,
}) async {
  final lib = context.read<LibraryProvider>();
  final playlistProvider = context.read<PlaylistProvider>();
  final l = AppLocalizations.of(context)!;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      // Cap height at 90 percent of the screen and scroll on small phones.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              song.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(l.songOptionsPlayNext),
            onTap: () {
              PlayerService.instance.playNext(song);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.songOptionsAddedPlayNext)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_check),
            title: Text(l.songOptionsAddToQueueEnd),
            onTap: () {
              PlayerService.instance.addToQueueEnd(song);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.songOptionsAddedToQueue)),
              );
            },
          ),
          ListTile(
            leading: Icon(song.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: song.isFavorite ? Colors.red : null),
            title: Text(song.isFavorite ? l.songOptionsRemoveFavorite : l.songOptionsAddFavorite),
            onTap: () async {
              try {
                await lib.toggleFavorite(song, !song.isFavorite);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.songOptionsFavoriteFailed(e.toString()))),
                  );
                }
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: Text(l.songOptionsAddToPlaylist),
            onTap: () async {
              Navigator.pop(ctx);
              pickPlaylist(context, song, playlistProvider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: Text(l.songOptionsRename),
            onTap: () async {
              Navigator.pop(ctx);
              _renameSong(context, song, lib);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(l.songOptionsEditMetadata),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => EditMetadataScreen(song: song)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: Text(l.songOptionsScanMetadata),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                final limited = await lib.rescanSingleMetadata(song);
                if (!context.mounted) return;
                final snack = limited
                    ? l.editMetadataRescanRateLimited
                    : l.artRefreshed;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(snack)),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(l.editMetadataRescanFailed(e.toString()))),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(l.songShare),
            onTap: () async {
              Navigator.pop(ctx);
              await _shareSong(context, song);
            },
          ),
          if (playlistId != null)
            ListTile(
              leading: const Icon(Icons.playlist_remove, color: Colors.red),
              title: Text(l.songOptionsRemoveFromPlaylist, style: const TextStyle(color: Colors.red)),
              onTap: () async {
                try {
                  await playlistProvider.removeSong(playlistId, song.id);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.songOptionsRemoveFromPlaylistFailed(e.toString()))),
                    );
                  }
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.songOptionsRemovedFromPlaylist)),
                );
              },
            ),
          if (showFullDelete)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(l.songOptionsDeleteFromLibrary, style: const TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(l.songOptionsDeleteTitle),
                    content: Text(l.songOptionsDeleteConfirm(song.title)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: Text(l.delete)),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    await lib.deleteSong(song);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.songOptionsDeleteFailed(e.toString()))),
                      );
                    }
                  }
                }
              },
            ),
        ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _shareSong(BuildContext context, Song song) async {
  // Share "title - artist" text plus the audio file when it still exists.
  final text = '${song.title} - ${song.artist}';
  try {
    final file = File(song.filePath);
    if (await file.exists()) {
      await SharePlus.instance
          .share(ShareParams(files: [XFile(song.filePath)], text: text));
    } else {
      // File is gone, so share the text label only.
      await SharePlus.instance.share(ShareParams(text: text));
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)!
              .songShareFailed(e.toString()))),
    );
  }
}

Future<void> _renameSong(BuildContext context, Song song, LibraryProvider lib) async {
  final controller = TextEditingController(text: song.title);
  final l = AppLocalizations.of(context)!;
  try {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.songOptionsRename),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(l.save)),
        ],
      ),
    );
    final trimmed = newName?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == song.title) return;
    final oldTitle = song.title;
    song.title = trimmed;
    try {
      await lib.updateMetadata(song);
    } catch (e) {
      song.title = oldTitle;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.songOptionsRenameFailed(e.toString()))),
        );
      }
    }
  } finally {
    controller.dispose();
  }
}

Future<void> pickPlaylist(BuildContext context, Song song, PlaylistProvider provider) {
  final l = AppLocalizations.of(context)!;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      // Cap height at 90 percent of the screen and scroll long lists.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          for (final p in provider.playlists)
            ListTile(
              title: Text(p['name']),
              onTap: () async {
                try {
                  await provider.addSong(p['id'], song.id);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.songOptionsAddToPlaylistFailed(e.toString()))),
                    );
                  }
                  return;
                }
                // Guard the sheet context before closing it.
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l.songOptionsCreatePlaylist),
            onTap: () async {
              // Guard the sheet context before closing it.
              if (ctx.mounted) Navigator.pop(ctx);
              final controller = TextEditingController();
              try {
                final name = await showDialog<String>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(l.songOptionsPlaylistNameTitle),
                    content: TextField(controller: controller, autofocus: true),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
                      TextButton(onPressed: () => Navigator.pop(c, controller.text), child: Text(l.create)),
                    ],
                  ),
                );
                final trimmed = name?.trim() ?? '';
                if (trimmed.isEmpty || !context.mounted) return;
                try {
                  // Take the id from the insert result - not playlists.first,
                  // because load order (createdAt DESC) is not guaranteed.
                  final newId = await DBHelper.instance.createPlaylist(trimmed);
                  await provider.load();
                  await provider.addSong(newId, song.id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.songOptionsPlaylistCreated(trimmed))),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  final msg = e.toString().contains('UNIQUE')
                      ? l.songOptionsPlaylistExists(trimmed)
                      : l.songOptionsCreatePlaylistFailed(e.toString());
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg)),
                  );
                }
              } finally {
                controller.dispose();
              }
            },
          ),
            ],
          ),
        ),
      ),
    ),
  );
}
