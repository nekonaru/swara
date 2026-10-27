import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';

class EditLyricsScreen extends StatefulWidget {
  final Song song;
  const EditLyricsScreen({super.key, required this.song});

  @override
  State<EditLyricsScreen> createState() => _EditLyricsScreenState();
}

class _EditLyricsScreenState extends State<EditLyricsScreen> {
  late final TextEditingController _controller;

  /// Lyrics length cap (100KB) so the DB does not bloat - same as the
  /// cap in MetadataService.fetchLyricsOnly.
  static const _kMaxLyricsChars = 100 * 1024;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.song.lyrics ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final clipboardText = data?.text ?? '';
    if (clipboardText.trim().isEmpty) {
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.editLyricsClipboardEmpty)),
      );
      return;
    }

    if (_controller.text.trim().isEmpty) {
      // No lyrics yet, paste directly
      setState(() => _controller.text = clipboardText);
      return;
    }

    // Lyrics already exist - ask whether to overwrite or append
    final l = AppLocalizations.of(context)!;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.editLyricsPasteTitle),
        content: Text(l.editLyricsPasteMessage),
        // Stack the three actions vertically on narrow screens.
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, 'append'), child: Text(l.editLyricsAppend)),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'overwrite'), child: Text(l.editLyricsOverwrite)),
        ],
      ),
    );
    if (choice == 'overwrite') {
      setState(() => _controller.text = clipboardText);
    } else if (choice == 'append') {
      setState(() => _controller.text = '${_controller.text}\n$clipboardText');
    }
  }

  Future<void> _searchOnWeb() async {
    final query = Uri.encodeComponent('${widget.song.artist} ${widget.song.title} lirik lyrics');
    final url = Uri.parse('https://www.google.com/search?q=$query');
    // No canLaunchUrl gate: on Android 11+ the http/https check always returns
    // false without a <queries> manifest entry, which blocked the browser.
    try {
      final launched =
          await launchUrl(url, mode: LaunchMode.externalApplication);
      if (launched || !mounted) return;
      _showSearchFailed();
    } catch (_) {
      if (!mounted) return;
      _showSearchFailed();
    }
  }

  void _showSearchFailed() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            AppLocalizations.of(context)!.editLyricsSearchOpenFailed),
      ),
    );
  }

  void _clear() {
    setState(() => _controller.clear());
  }

  Future<void> _save() async {
    var text = _controller.text.trim();
    var truncated = false;
    if (text.length > _kMaxLyricsChars) {
      text = text.substring(0, _kMaxLyricsChars);
      truncated = true;
    }
    final newLyrics = text.isEmpty ? null : text;

    // Save via a copy first - widget.song.lyrics is only mutated after DB success.
    final s = widget.song;
    final updated = Song(
      id: s.id,
      filePath: s.filePath,
      title: s.title,
      artist: s.artist,
      album: s.album,
      genre: s.genre,
      region: s.region,
      albumArtPath: s.albumArtPath,
      albumArtUrl: s.albumArtUrl,
      lyrics: newLyrics,
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
          SnackBar(content: Text(l.editLyricsSaveFailed(e.toString()))),
        );
      }
      return;
    }
    s.lyrics = newLyrics;
    if (!mounted) return;
    // ScaffoldMessenger lives above the route, so the snackbar still shows
    // on the previous screen even though this page is popped immediately.
    if (truncated) {
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.editLyricsTruncated)),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.editLyricsTitle(widget.song.title)),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste),
                  label: Text(l.editLyricsPasteButton),
                ),
                OutlinedButton.icon(
                  onPressed: _searchOnWeb,
                  icon: const Icon(Icons.search),
                  label: Text(l.editLyricsSearchWeb),
                ),
                OutlinedButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.close),
                  label: Text(l.delete),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: l.editLyricsHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _save,
              child: Text(l.editLyricsSaveButton),
            ),
          ),
        ],
      ),
    );
  }
}
