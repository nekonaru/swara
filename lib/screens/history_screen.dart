import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import '../models/song.dart';
import '../services/db_helper.dart';
import '../services/player_service.dart';
import '../utils/song_options.dart';
import '../utils/format.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<Song> _history = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Called from HomeScreen whenever the History tab is selected, so a
  /// newly played song appears immediately without manual pull-to-refresh.
  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final history = await DBHelper.instance.getRecentlyPlayed();
      if (!mounted) return;
      setState(() {
        _history = history;
        _error = null;
      });
    } catch (e) {
      // Corrupt/broken DB - show an error message instead of a red screen.
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.historyLoadFailed(_error!), textAlign: TextAlign.center),
        ),
      );
    }
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(l.historyEmpty, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _history.length,
        itemBuilder: (context, i) {
          final song = _history[i];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatDuration(song.durationMs), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                IconButton(
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showSongOptions(context, song),
                ),
              ],
            ),
            // The play call opens the file, so it can throw when the file is gone.
            // Without a catch the user would see the tap do nothing at all.
            onTap: () async {
              try {
                await PlayerService.instance
                    .setQueueAndPlay(_history, i);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context)!
                        .historyPlayFailed(e.toString())),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}
