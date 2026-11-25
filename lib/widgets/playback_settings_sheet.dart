import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';

import '../services/db_helper.dart';
import '../services/player_service.dart';

/// Edit gain and skip intro/outro for one song or one folder. All values are
/// local and take effect immediately after saving via PlayerService refresh.
class PlaybackSettingsSheet extends StatefulWidget {
  final int? songId;
  final String? folderPath;
  final String title;
  final int durationMs;
  final double initialGainDb;
  final int initialSkipStartMs;
  final int initialSkipEndMs;

  const PlaybackSettingsSheet({
    super.key,
    this.songId,
    this.folderPath,
    required this.title,
    required this.durationMs,
    required this.initialGainDb,
    required this.initialSkipStartMs,
    required this.initialSkipEndMs,
  }) : assert(songId != null || folderPath != null);

  static Future<void> show(
    BuildContext context, {
    int? songId,
    String? folderPath,
    required String title,
    required int durationMs,
    required double gainDb,
    required int skipStartMs,
    required int skipEndMs,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PlaybackSettingsSheet(
        songId: songId,
        folderPath: folderPath,
        title: title,
        durationMs: durationMs,
        initialGainDb: gainDb,
        initialSkipStartMs: skipStartMs,
        initialSkipEndMs: skipEndMs,
      ),
    );
  }

  @override
  State<PlaybackSettingsSheet> createState() => _PlaybackSettingsSheetState();
}

class _PlaybackSettingsSheetState extends State<PlaybackSettingsSheet> {
  late double _gain = widget.initialGainDb.clamp(-12.0, 6.0);
  late double _start = (widget.initialSkipStartMs / 1000).round().toDouble();
  late double _end = (widget.initialSkipEndMs / 1000).round().toDouble();
  bool _saving = false;

  double get _maxSeconds {
    final whole = widget.durationMs / 1000;
    return whole > 0 ? (whole / 2).clamp(0.0, 600.0) : 600.0;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final startMs = (_start * 1000).round();
    final endMs = (_end * 1000).round();
    try {
      if (widget.songId != null) {
        await DBHelper.instance.setSongPlaybackSettings(
          widget.songId!,
          gainDb: _gain,
          skipStartMs: startMs,
          skipEndMs: endMs,
        );
      } else {
        await DBHelper.instance.setFolderPlaybackSettings(
          widget.folderPath!,
          gainDb: _gain,
          skipStartMs: startMs,
          skipEndMs: endMs,
        );
      }
      await PlayerService.instance.refreshPlaybackSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 2),
              content: Text(
                  AppLocalizations.of(context)!.playbackSettingsSaved)),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 2),
              content: Text(
                  AppLocalizations.of(context)!.dataFailedGeneric)),
        );
      }
    }
  }

  Future<void> _reset() async {
    try {
      if (widget.songId != null) {
        await DBHelper.instance.clearSongPlaybackSettings(widget.songId!);
      } else {
        await DBHelper.instance.clearFolderPlaybackSettings(widget.folderPath!);
      }
      await PlayerService.instance.refreshPlaybackSettings();
      if (mounted) Navigator.pop(context);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final maxSeconds = _maxSeconds;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              widget.songId != null
                  ? l.playbackSettingsSongSubtitle
                  : l.playbackSettingsFolderSubtitle,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text('${l.playbackSettingsGain}: ${_gain.toStringAsFixed(1)} dB'),
            Slider(
              value: _gain,
              min: -12,
              max: 6,
              divisions: 36,
              label: '${_gain.toStringAsFixed(1)} dB',
              onChanged: _saving ? null : (v) => setState(() => _gain = v),
            ),
            Text('${l.playbackSettingsSkipIntro}: ${_start.round()} s'),
            Slider(
              value: _start.clamp(0.0, maxSeconds),
              min: 0,
              max: maxSeconds,
              divisions: maxSeconds > 0 ? maxSeconds.round() : 1,
              onChanged: _saving ? null : (v) => setState(() => _start = v),
            ),
            Text('${l.playbackSettingsSkipOutro}: ${_end.round()} s'),
            Slider(
              value: _end.clamp(0.0, maxSeconds),
              min: 0,
              max: maxSeconds,
              divisions: maxSeconds > 0 ? maxSeconds.round() : 1,
              onChanged: _saving ? null : (v) => setState(() => _end = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(onPressed: _saving ? null : _reset, child: Text(l.playbackSettingsReset)),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(l.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
