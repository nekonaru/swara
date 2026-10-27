import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import '../services/player_service.dart';

enum _TimerMode { waktu, lagu, bedtime }

class SleepTimerSheet extends StatefulWidget {
  const SleepTimerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SleepTimerSheet(),
    );
  }

  @override
  State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet> {
  _TimerMode _mode = _TimerMode.waktu;
  bool _finishSong = false;
  Timer? _ticker;
  Timer? _bedtimeTicker;

  // Bedtime mode state. Persisted as "HH:MM" under the 'bedtime' key.
  // NOTE (limitation): the countdown is converted once into a plain
  // in-app sleep timer via setSleepTimer(), so it only runs while the
  // app process stays alive. If the app is killed, the timer does not
  // fire. No background task is scheduled here by design (keep it
  // simple, no over-engineering).
  static const String _bedtimePrefsKey = 'bedtime';
  TimeOfDay _bedtime = const TimeOfDay(hour: 22, minute: 0);

  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minCtrl;
  late final FixedExtentScrollController _songCtrl;

  static final List<int> _minuteOptions = List.generate(12, (i) => i * 5);
  static const int _defaultMinuteIndex = 3; // 15 menit
  static const int _defaultSongIndex = 4;   // 5 lagu

  @override
  void initState() {
    super.initState();
    _hourCtrl = FixedExtentScrollController(initialItem: 0);
    _minCtrl  = FixedExtentScrollController(initialItem: _defaultMinuteIndex);
    _songCtrl = FixedExtentScrollController(initialItem: _defaultSongIndex);

    // Seed the checkbox from the service, so an already running session never
    // shows a value the service is not actually using.
    _finishSong = PlayerService.instance.finishCurrentSongOnSleep;

    // One second ticker for the countdown, started unconditionally while the
    // sheet is open. It deliberately never cancels itself: a timer can start
    // after the sheet was built (for example the daily schedule firing at
    // 22:00 while the sheet stays open), and the build method below listens to
    // the service, so the ticker must still be running when that happens.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadBedtime();
    // Refresh the bedtime countdown text while the sheet is open.
    _bedtimeTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _mode == _TimerMode.bedtime && !_isTimerActive) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _bedtimeTicker?.cancel();
    _hourCtrl.dispose();
    _minCtrl.dispose();
    _songCtrl.dispose();
    super.dispose();
  }

  bool get _isTimerActive {
    final ps = PlayerService.instance;
    return ps.sleepTimerRemaining != null ||
        ps.sleepSongsRemaining != null ||
        ps.isSleepFadeOutActive;
  }

  // Load the saved bedtime ("HH:MM") or keep the 22:00 default.
  Future<void> _loadBedtime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bedtimePrefsKey);
      if (raw == null) return;
      final parts = raw.split(':');
      if (parts.length != 2) return;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
        return;
      }
      if (!mounted) return;
      setState(() => _bedtime = TimeOfDay(hour: h, minute: m));
    } catch (_) {
      // Keep the default bedtime when prefs are unavailable.
    }
  }

  Future<void> _saveBedtime(TimeOfDay t) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      await prefs.setString(_bedtimePrefsKey, raw);
    } catch (_) {
      // Persisting bedtime is best effort only.
    }
  }

  // Duration until the next bedtime: today when still ahead, else tomorrow.
  Duration _durationUntilBedtime() {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, _bedtime.hour, _bedtime.minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target.difference(now);
  }

  // Short countdown label, localized units.
  String _fmtBedtimeCountdown(
      AppLocalizations l10n, Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return l10n.bedtimeCountdownHours(h, m);
    if (m > 0) return l10n.bedtimeCountdownMinutes(m, s);
    return l10n.bedtimeCountdownSeconds(s);
  }

  String _fmtBedtime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickBedtime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _bedtime,
    );
    if (picked == null) return;
    await _saveBedtime(picked);
    if (!mounted) return;
    setState(() => _bedtime = picked);
  }

  void _startBedtime() {
    final duration = _durationUntilBedtime();
    if (duration <= Duration.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)!.bedtimePickFuture)),
      );
      return;
    }
    PlayerService.instance
        .setSleepTimer(duration, finishCurrentSong: _finishSong);
    Navigator.pop(context);
  }

  void _start() {
    final ps = PlayerService.instance;
    if (_mode == _TimerMode.bedtime) {
      _startBedtime();
      return;
    }
    if (_mode == _TimerMode.waktu) {
      final hours   = _hourCtrl.selectedItem;
      final minutes = _minuteOptions[_minCtrl.selectedItem];
      final total   = hours * 60 + minutes;
      if (total == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.sleepSetTimeAboveZero)),
        );
        return;
      }
      ps.setSleepTimer(Duration(minutes: total), finishCurrentSong: _finishSong);
    } else {
      ps.setSleepTimerBySongs(_songCtrl.selectedItem + 1);
    }
    Navigator.pop(context);
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Listen to the service for the whole sheet: a timer can start, end or
    // change mode from anywhere (including the daily schedule) while this
    // sheet stays open, and the view must always match the service state.
    return AnimatedBuilder(
      animation: PlayerService.instance,
      builder: (context, _) => _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ps = PlayerService.instance;
    final isActive = _isTimerActive;

    return Container(
      constraints: BoxConstraints(
        // Cap height at 90 percent of the screen and scroll on small phones.
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Align(
            alignment: Alignment.centerLeft,
            child: Text(AppLocalizations.of(context)!.sleepTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),

          // Content: active timer OR picker
          if (isActive)
            _buildActiveState(ps, cs)
          else
            _buildPickerState(cs),

          const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // ACTIVE STATE: Countdown + Stop
  // ----------------------------------------------------------

  Widget _buildActiveState(PlayerService ps, ColorScheme cs) {
    final remaining  = ps.sleepTimerRemaining;
    final songsLeft  = ps.sleepSongsRemaining;
    final isFading = ps.isSleepFadeOutActive;
    final isTimeMode = remaining != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Large countdown
        if (isTimeMode) ...[
          Text(
            _fmt(remaining),
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(AppLocalizations.of(context)!.sleepRemaining, style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          const SizedBox(height: 20),
          // Finish-last-song checkbox. Updates local state for the UI and
          // forwards the value to the service so the running timer follows it.
          InkWell(
            onTap: () {
              final next = !_finishSong;
              setState(() => _finishSong = next);
              PlayerService.instance.setFinishCurrentSongOnSleep(next);
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 24, height: 24,
                    child: Checkbox(
                      value: _finishSong,
                      onChanged: (v) {
                        final next = v ?? false;
                        setState(() => _finishSong = next);
                        PlayerService.instance.setFinishCurrentSongOnSleep(next);
                      },
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(AppLocalizations.of(context)!.sleepFinishLastSong,
                      style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ] else if (isFading) ...[
          // Sleep fade out in progress, timer already expired.
          Text(
            AppLocalizations.of(context)!.sleepFadingOut,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(AppLocalizations.of(context)!.sleepStoppingPlayback,
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ] else ...[
          // Song mode
          Text(
            '${songsLeft ?? 0}',
            style: const TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(AppLocalizations.of(context)!.sleepSongsRemaining,
              style: TextStyle(fontSize: 16, color: Colors.grey[500])),
        ],
        const SizedBox(height: 24),

        // Buttons: Close | Stop
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(AppLocalizations.of(context)!.close,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  ps.cancelSleepTimer();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(AppLocalizations.of(context)!.sleepTimerStopped),
                        duration: const Duration(seconds: 2)),
                  );
                },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.red[700],
                ),
                child: Text(AppLocalizations.of(context)!.sleepStop,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // PICKER STATE: Set a new timer
  // ----------------------------------------------------------

  Widget _buildPickerState(ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mode toggle: Time | Songs | Bedtime
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              _ModeButton(
                label: AppLocalizations.of(context)!.sleepTimeMode,
                selected: _mode == _TimerMode.waktu,
                onTap: () => setState(() => _mode = _TimerMode.waktu),
                color: cs.primary,
              ),
              _ModeButton(
                label: AppLocalizations.of(context)!.sleepSongMode,
                selected: _mode == _TimerMode.lagu,
                onTap: () => setState(() => _mode = _TimerMode.lagu),
                color: cs.primary,
              ),
              _ModeButton(
                label: AppLocalizations.of(context)!.bedtimeMode,
                selected: _mode == _TimerMode.bedtime,
                onTap: () => setState(() => _mode = _TimerMode.bedtime),
                color: cs.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Picker wheel
        SizedBox(
          height: 160,
          child: _mode == _TimerMode.waktu
              ? _buildTimePicker(cs)
              : _mode == _TimerMode.lagu
                  ? _buildSongPicker(cs)
                  : _buildBedtimePicker(cs),
        ),
        const SizedBox(height: 12),

        // Finish-song checkbox - time and bedtime modes only
        if (_mode == _TimerMode.waktu || _mode == _TimerMode.bedtime)
          InkWell(
            onTap: () => setState(() => _finishSong = !_finishSong),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 24, height: 24,
                    child: Checkbox(
                      value: _finishSong,
                      onChanged: (v) => setState(() => _finishSong = v ?? false),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(AppLocalizations.of(context)!.sleepFinishLastSong,
                      style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),

        // Daily schedule: an always available switch next to the one shot
        // timer above, so a bedtime can be armed without starting it now.
        const _DailyScheduleSection(),
        const SizedBox(height: 20),

        // Close | Start
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(AppLocalizations.of(context)!.close,
                    style: TextStyle(
                        color: cs.onSurface, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _start,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(AppLocalizations.of(context)!.sleepStart,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimePicker(ColorScheme cs) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 52),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 100,
              child: _WheelPicker(
                controller: _hourCtrl,
                itemCount: 13,
                labelBuilder: (i) => '$i',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(':',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
            ),
            SizedBox(
              width: 100,
              child: _WheelPicker(
                controller: _minCtrl,
                itemCount: _minuteOptions.length,
                labelBuilder: (i) =>
                    _minuteOptions[i].toString().padLeft(2, '0'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Bedtime mode: pick a clock time, show the countdown to its next
  // occurrence, and start a plain in-app timer for that duration.
  Widget _buildBedtimePicker(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final countdown =
        _fmtBedtimeCountdown(l10n, _durationUntilBedtime());
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _pickBedtime,
          icon: const Icon(Icons.bedtime_outlined),
          label: Text(
            '${l10n.bedtimeMode} ${_fmtBedtime(_bedtime)}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.bedtimeStopsIn(countdown),
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.bedtimeAppOpenNote,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildSongPicker(ColorScheme cs) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 52),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              child: _WheelPicker(
                controller: _songCtrl,
                itemCount: 100,
                labelBuilder: (i) => '${i + 1}',
              ),
            ),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(context)!.sleepSongUnit,
                style: TextStyle(
                    fontSize: 16,
                    color: cs.onSurface.withValues(alpha: 0.7))),
          ],
        ),
      ],
    );
  }
}

// -------------------------------------------------------------
// Drum-roll wheel picker
// -------------------------------------------------------------

class _WheelPicker extends StatefulWidget {
  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int) labelBuilder;
  const _WheelPicker(
      {required this.controller,
      required this.itemCount,
      required this.labelBuilder});
  @override
  State<_WheelPicker> createState() => _WheelPickerState();
}

class _WheelPickerState extends State<_WheelPicker> {
  int _sel = 0;
  @override
  void initState() {
    super.initState();
    _sel = widget.controller.initialItem;
    widget.controller.addListener(_onScroll);
  }
  void _onScroll() {
    if (mounted) setState(() => _sel = widget.controller.selectedItem);
  }
  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListWheelScrollView.useDelegate(
      controller: widget.controller,
      itemExtent: 52,
      physics: const FixedExtentScrollPhysics(),
      perspective: 0.002,
      diameterRatio: 2.5,
      overAndUnderCenterOpacity: 0.35,
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          if (index < 0 || index >= widget.itemCount) return null;
          final isSel = index == _sel;
          return AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              fontSize: isSel ? 26 : 18,
              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
              color: isSel ? cs.onSurface : cs.onSurface.withValues(alpha: 0.35),
            ),
            child: Center(child: Text(widget.labelBuilder(index))),
          );
        },
        childCount: widget.itemCount,
      ),
    );
  }
}

// -------------------------------------------------------------
// Daily schedule section
// -------------------------------------------------------------

class _DailyScheduleSection extends StatelessWidget {
  const _DailyScheduleSection();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final ps = PlayerService.instance;
    // Rebuild whenever the service notifies so the switch and the time
    // follow changes made from anywhere else in the app.
    return AnimatedBuilder(
      animation: ps,
      builder: (context, _) {
        final enabled = ps.sleepScheduleEnabled;
        final time = '${ps.sleepScheduleHour.toString().padLeft(2, '0')}:'
            '${ps.sleepScheduleMinute.toString().padLeft(2, '0')}';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.sleepDailySchedule),
              subtitle: Text(l10n.sleepDailyScheduleSubtitle),
              secondary: const Icon(Icons.schedule),
              value: enabled,
              onChanged: (v) => ps.setSleepScheduleEnabled(v),
            ),
            // The time button stays disabled until the schedule is armed.
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed:
                    enabled ? () => _pickScheduleTime(context) : null,
                icon: const Icon(Icons.access_time, size: 18),
                label: Text(enabled ? time : l10n.sleepDailyScheduleSetTime),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.sleepDailyScheduleHint,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _pickScheduleTime(BuildContext context) async {
    final ps = PlayerService.instance;
    final picked = await showTimePicker(
      context: context,
      // 24 hour picker, matching the bedtime mode above.
      initialTime: TimeOfDay(
        hour: ps.sleepScheduleHour,
        minute: ps.sleepScheduleMinute,
      ),
    );
    if (picked == null) return;
    // PlayerService persists the new hour and minute.
    await ps.setSleepScheduleTime(picked.hour, picked.minute);
  }
}

// -------------------------------------------------------------
// Time/Songs toggle
// -------------------------------------------------------------

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const _ModeButton(
      {required this.label,
      required this.selected,
      required this.onTap,
      required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-level function for compatibility with the existing caller (player_screen.dart).
Future<void> showSleepTimerSheet(BuildContext context) =>
    SleepTimerSheet.show(context);
