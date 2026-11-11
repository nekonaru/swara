import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../services/db_helper.dart';
import '../services/metadata_service.dart';

import '../services/embedded_art_service.dart';

// Screen listing songs that have no cover art, with per song and bulk refetch.
class MissingArtScreen extends StatefulWidget {
  const MissingArtScreen({super.key});

  @override
  State<MissingArtScreen> createState() => _MissingArtScreenState();
}

bool _hasNoArt(Song s) {
  final path = (s.albumArtPath ?? '').trim();
  final url = (s.albumArtUrl ?? '').trim();
  if (path.isNotEmpty || url.isNotEmpty) return false;
  // A known extracted embedded cover means there is art; the rest of the
  // embedded art is probed lazily as rows render, so the list gets more
  // accurate as the user browses.
  if (EmbeddedArtService.instance.peekSync(s.id) != null) return false;
  return true;
}

class _MissingArtScreenState extends State<MissingArtScreen> {
  // Ids currently being refreshed, to show a spinner on that tile only.
  final Set<int> _refreshingIds = {};
  // Bulk fetch progress state. Simple counters only, no extra dependency.
  bool _fetchingAll = false;
  int _done = 0;
  int _total = 0;
  // Set by the stop control in the app bar, checked before every song so a
  // bulk fetch can be interrupted. Everything already fetched is kept,
  // because enrichSong stores each song as it completes.
  bool _cancelRequested = false;

  // Cached filter result, rebuilt only when the library version changes.
  // Scanning progress notifications rebuild this Consumer often, and the
  // filter walks every song each time.
  List<Song> _missingCache = const <Song>[];
  int _missingVersion = -1;

  List<Song> _missing(LibraryProvider lib) {
    if (_missingVersion != lib.songsVersion) {
      _missingVersion = lib.songsVersion;
      _missingCache = lib.songs.where(_hasNoArt).toList();
    }
    return _missingCache;
  }

  Future<void> _refreshOne(Song song) async {
    if (_refreshingIds.contains(song.id)) return;
    setState(() => _refreshingIds.add(song.id));
    try {
      // Single song enrich via the existing provider API, which reloads the DB.
      await context.read<LibraryProvider>().rescanSingleMetadata(song);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.artRefreshed),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!
              .artRefreshFailed(e.toString())),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _refreshingIds.remove(song.id));
      } else {
        _refreshingIds.remove(song.id);
      }
    }
  }

  Future<void> _fetchAll(List<Song> targets) async {
    if (_fetchingAll || targets.isEmpty) return;
    setState(() {
      _fetchingAll = true;
      _cancelRequested = false;
      _done = 0;
      _total = targets.length;
    });
    var stoppedEarly = false;
    var cancelled = false;
    try {
      // Sequential enrich in small batches. enrichSong returns true on 429
      // (or active backoff), so stop at once and keep leftovers for later.
      const batchSize = 5;
      for (var i = 0; i < targets.length; i += batchSize) {
        final end =
            (i + batchSize) < targets.length ? i + batchSize : targets.length;
        final batch = targets.sublist(i, end);
        for (final song in batch) {
          // A stop request ends the run before the next song starts. What
          // was already fetched stays stored, so the count is not wasted.
          if (_cancelRequested) {
            cancelled = true;
            break;
          }
          final limited = await MetadataService.instance.enrichSong(song);
          // enrichSong only upserts file facts; persist the filled fields,
          // otherwise the list reverts on the next reload.
          try {
            await DBHelper.instance.applyEnrichedMetadata(song);
          } catch (e) {
            debugPrint('Missing art persist failed for ${song.id}: $e');
          }
          if (limited) {
            stoppedEarly = true;
            break;
          }
          if (mounted) {
            setState(() => _done += 1);
          } else {
            _done += 1;
          }
        }
        if (stoppedEarly || cancelled) break;
      }
      // Reload once so the list reflects newly fetched covers.
      if (!mounted) return;
      await context.read<LibraryProvider>().loadFromDb();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cancelled
              ? l10n.scanStopped
              : stoppedEarly
                  ? l10n.artFetchStopped(_done, _total)
                  : l10n.artFetchFinished(_done, _total)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!
              .artFetchFailed(e.toString())),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _fetchingAll = false;
          _cancelRequested = false;
        });
      } else {
        _fetchingAll = false;
        _cancelRequested = false;
      }
    }
  }

  // Ask the running bulk fetch to stop at the next song. The button shows a
  // spinner from then on so a second tap cannot race the shutdown.
  void _cancelFetch() {
    if (!_fetchingAll || _cancelRequested) return;
    setState(() => _cancelRequested = true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, lib, _) {
        final missing = _missing(lib);
        return Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.of(context)!.artMissingTitle),
            actions: [
              // While a fetch runs this button becomes the stop control: the
              // count keeps showing progress, and pressing it ends the run
              // without losing what was already fetched.
              TextButton.icon(
                onPressed: missing.isEmpty
                    ? null
                    : _fetchingAll
                        ? _cancelFetch
                        : () => _fetchAll(missing),
                icon: _fetchingAll
                    ? (_cancelRequested
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.stop, size: 18))
                    : const Icon(Icons.cloud_download_outlined, size: 18),
                label: Text(_fetchingAll
                    ? '$_done/$_total'
                    : AppLocalizations.of(context)!.artFetchAll),
              ),
            ],
            bottom: _fetchingAll && _total > 0
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(4),
                    child: LinearProgressIndicator(value: _done / _total),
                  )
                : null,
          ),
          body: missing.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.image_search,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context)!.artAllHaveCovers),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: missing.length,
                  itemBuilder: (context, i) {
                    final song = missing[i];
                    final busy = _refreshingIds.contains(song.id);
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: const CircleAvatar(
                        child: Icon(Icons.music_note, size: 20),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${song.artist} - ${song.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              constraints: const BoxConstraints(
                                  minWidth: 48, minHeight: 48),
                              icon: const Icon(Icons.refresh, size: 20),
                              tooltip:
                                  AppLocalizations.of(context)!.artRefetch,
                              onPressed: _fetchingAll
                                  ? null
                                  : () => _refreshOne(song),
                            ),
                    );
                  },
                ),
        );
      },
    );
  }
}
