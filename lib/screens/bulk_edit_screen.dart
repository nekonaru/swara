import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../services/db_helper.dart';

// Bulk edit screen for genre and artist across many songs at once.
// Empty field means do not change that field for any song.
class BulkEditScreen extends StatefulWidget {
  final List<Song> songs;
  const BulkEditScreen({super.key, required this.songs});

  @override
  State<BulkEditScreen> createState() => _BulkEditScreenState();
}

class _BulkEditScreenState extends State<BulkEditScreen> {
  late TextEditingController _genre;
  late TextEditingController _artist;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _genre = TextEditingController();
    _artist = TextEditingController();
  }

  @override
  void dispose() {
    _genre.dispose();
    _artist.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final genre = _genre.text.trim();
    final artist = _artist.text.trim();
    // Reject when both fields are empty since nothing would change.
    if (genre.isEmpty && artist.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.bulkEditValidate)),
      );
      return;
    }
    setState(() => _saving = true);
    int ok = 0;
    int failed = 0;
    try {
      final lib = context.read<LibraryProvider>();
      // Build every updated row first, then write them all in one batch and
      // reload the library once. The previous per song path reloaded the whole
      // library for every row, which froze the UI on a large selection.
      final updates = <Song>[];
      for (final s in widget.songs) {
        updates.add(Song(
          id: s.id,
          filePath: s.filePath,
          title: s.title,
          artist: artist.isEmpty ? s.artist : artist,
          album: s.album,
          genre: genre.isEmpty ? s.genre : genre,
          region: s.region,
          albumArtPath: s.albumArtPath,
          albumArtUrl: s.albumArtUrl,
          lyrics: s.lyrics,
          durationMs: s.durationMs,
          isFavorite: s.isFavorite,
          addedAt: s.addedAt,
          metadataScanned: s.metadataScanned,
        ));
      }
      try {
        await DBHelper.instance.updateSongMetadataBulk(updates);
        await lib.loadFromDb();
        ok = updates.length;
        // Keep the list items in sync after the write succeeded.
        for (final s in widget.songs) {
          if (artist.isNotEmpty) s.artist = artist;
          if (genre.isNotEmpty) s.genre = genre;
        }
      } catch (_) {
        failed = widget.songs.length;
      }
    } catch (_) {
      // A provider level failure counts every remaining song as failed.
      failed += widget.songs.length - ok - failed;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)!
              .bulkEditSummary(ok, failed))),
    );
    if (ok > 0) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!
            .bulkEditTitle(widget.songs.length)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Empty hint so users know blank fields are skipped.
          Text(AppLocalizations.of(context)!.bulkEditHint),
          const SizedBox(height: 16),
          TextField(
            controller: _genre,
            decoration: InputDecoration(
                labelText:
                    AppLocalizations.of(context)!.bulkEditGenre),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _artist,
            decoration: InputDecoration(
                labelText:
                    AppLocalizations.of(context)!.bulkEditArtist),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _apply,
            child: Text(_saving
                ? AppLocalizations.of(context)!.bulkEditApplying
                : AppLocalizations.of(context)!.bulkEditApply),
          ),
        ],
      ),
    );
  }
}
