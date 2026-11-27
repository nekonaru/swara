import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:swara/l10n/v5_strings.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../services/tag_write_service.dart';
import '../services/db_helper.dart';
import '../services/extra_features_service.dart';
import '../services/embedded_art_service.dart';
import '../services/player_service.dart';
import 'edit_lyrics_screen.dart';

class EditMetadataScreen extends StatefulWidget {
  final Song song;
  const EditMetadataScreen({super.key, required this.song});

  @override
  State<EditMetadataScreen> createState() => _EditMetadataScreenState();
}

class _EditMetadataScreenState extends State<EditMetadataScreen> {
  bool _writeToFile = true;
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

  Future<void> _pickCustomCover() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty) return;
      final bytes = await picked.first.readAsBytes();
      if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) return;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}custom_covers');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = p.extension(picked.first.name);
      final safeExt = ext.isEmpty || ext.length > 5 ? '.jpg' : ext;
      final file = File('${dir.path}${Platform.pathSeparator}'
          '${widget.song.id}$safeExt');
      await file.writeAsBytes(bytes);
      // Drop the previous cover file so repeated edits do not leak copies.
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('${widget.song.id}.') &&
            entity.path != file.path) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
      await DBHelper.instance.setAlbumArtPath(widget.song.id, file.path);
      widget.song.albumArtPath = file.path;
      EmbeddedArtService.instance.evict(widget.song.id);
      if (!mounted) return;
      await context.read<LibraryProvider>().loadFromDb();
      PlayerService.instance.rebroadcastState();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(V5.coverSaved)));
    } catch (_) {}
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    final title = _title.text.trim();
    final artist = _artist.text.trim();
    final album = _album.text.trim();
    final genre = _genre.text.trim().isEmpty ? null : _genre.text.trim();
    final region = _region.text.trim().isEmpty ? null : _region.text.trim();

    if (title.isEmpty || artist.isEmpty || album.isEmpty) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
          SnackBar(duration: const Duration(seconds: 2),content: Text(l.editMetadataValidationEmpty)),
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
      rating: s.rating,
    );
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<LibraryProvider>();
    TagWriteResult writeResult = const TagWriteResult(status: TagWriteStatus.dbOnly);
    try {
      writeResult = await provider.writeTagsAndUpdate(
        updated,
        writeToFile: _writeToFile,
      );
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
          SnackBar(duration: const Duration(seconds: 2),content: Text(l.editMetadataSaveFailed(e.toString()))),
        );
      }
      return;
    }
    s.title = title;
    s.artist = artist;
    s.album = album;
    s.genre = genre;
    s.region = region;
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(writeResult.osWritten
            ? l.editMetadataTagsWritten
            : l.editMetadataTagsDbOnly(writeResult.error ?? 'unsupported')),
      ));
    Navigator.pop(context);
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
      ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
        SnackBar(duration: const Duration(seconds: 2),content: Text(l.editMetadataRescanFailed(e.toString()))),
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
    ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
      SnackBar(duration: const Duration(seconds: 2),
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
          IconButton(icon: const Icon(Icons.check), tooltip: AppLocalizations.of(context)!.save, onPressed: _save),
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
          SwitchListTile(
            title: Text(l.editMetadataWriteToFile),
            value: _writeToFile,
            onChanged: (value) => setState(() => _writeToFile = value),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickCustomCover,
            icon: const Icon(Icons.image_outlined),
            label: Text(V5.customCover),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final parsed = FilenameTagService.parse(
                  p.basename(widget.song.filePath));
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(V5.parseFilename),
                  content: Text(V5.parsedPreview(parsed.artist, parsed.title)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(l.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(V5.applyParsed),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              setState(() {
                _title.text = parsed.title;
                if (parsed.artist.isNotEmpty) _artist.text = parsed.artist;
              });
            },
            icon: const Icon(Icons.text_snippet_outlined),
            label: Text(V5.parseFilename),
          ),
          const SizedBox(height: 8),
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
