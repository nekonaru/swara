import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import 'edit_lyrics_screen.dart';

class EditMetadataScreen extends StatefulWidget {
  final Song song;
  const EditMetadataScreen({super.key, required this.song});

  @override
  State<EditMetadataScreen> createState() => _EditMetadataScreenState();
}

class _EditMetadataScreenState extends State<EditMetadataScreen> {
  late TextEditingController _title;
  late TextEditingController _artist;
  late TextEditingController _album;
  late TextEditingController _genre;
  late TextEditingController _region;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    final s = widget.song;
    _title = TextEditingController(text: s.title);
    _artist = TextEditingController(text: s.artist);
    _album = TextEditingController(text: s.album);
    _genre = TextEditingController(text: s.genre ?? '');
    _region = TextEditingController(text: s.region ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _genre.dispose();
    _region.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final artist = _artist.text.trim();
    final album = _album.text.trim();
    final genre = _genre.text.trim().isEmpty ? null : _genre.text.trim();
    final region = _region.text.trim().isEmpty ? null : _region.text.trim();

    if (title.isEmpty || artist.isEmpty || album.isEmpty) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.editMetadataValidationEmpty)),
        );
      }
      return;
    }

    // Copy into a separate object first - widget.song is only mutated after
    // the DB write succeeds, so memory is not dirtied when saving fails.
    final s = widget.song;
    final updated = Song(
      id: s.id,
      filePath: s.filePath,
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      region: region,
      albumArtPath: s.albumArtPath,
      albumArtUrl: s.albumArtUrl,
      lyrics: s.lyrics,
      durationMs: s.durationMs,
      isFavorite: s.isFavorite,
      addedAt: s.addedAt,
      metadataScanned: s.metadataScanned,
    );
    try {
      await context.read<LibraryProvider>().updateMetadata(updated);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.editMetadataSaveFailed(e.toString()))),
        );
      }
      return;
    }
    s.title = title;
    s.artist = artist;
    s.album = album;
    s.genre = genre;
    s.region = region;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _rescanFromInternet() async {
    // Rescanning overwrites manual edits - ask for confirmation first.
    final l = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.editMetadataRescanTitle),
        content: Text(l.editMetadataRescanMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.editMetadataRescanConfirm)),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _isScanning = true);
    bool limited;
    try {
      limited =
          await context.read<LibraryProvider>().rescanSingleMetadata(widget.song);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.editMetadataRescanFailed(e.toString()))),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _title.text = widget.song.title;
      _artist.text = widget.song.artist;
      _album.text = widget.song.album;
      _genre.text = widget.song.genre ?? '';
      _region.text = widget.song.region ?? '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(limited
            ? AppLocalizations.of(context)!.editMetadataRescanRateLimited
            : l.editMetadataRescanSuccess),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.editMetadataTitle),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.tonalIcon(
            onPressed: _isScanning ? null : _rescanFromInternet,
            icon: _isScanning
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_sync_outlined),
            label: Text(_isScanning ? l.editMetadataFetching : l.editMetadataRescanButton),
          ),
          const SizedBox(height: 16),
          TextField(controller: _title, decoration: InputDecoration(labelText: l.editMetadataFieldTitle)),
          const SizedBox(height: 12),
          TextField(controller: _artist, decoration: InputDecoration(labelText: l.editMetadataFieldArtist)),
          const SizedBox(height: 12),
          TextField(controller: _album, decoration: InputDecoration(labelText: l.editMetadataFieldAlbum)),
          const SizedBox(height: 12),
          TextField(controller: _genre, decoration: InputDecoration(labelText: l.editMetadataFieldGenre)),
          const SizedBox(height: 12),
          TextField(controller: _region, decoration: InputDecoration(labelText: l.editMetadataFieldRegion)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditLyricsScreen(song: widget.song)),
            ),
            icon: const Icon(Icons.lyrics_outlined),
            label: Text(l.editMetadataEditLyricsButton),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(l.editMetadataSaveButton)),
        ],
      ),
    );
  }
}
