import 'package:flutter/material.dart';
import '../utils/motion.dart';
import 'package:provider/provider.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import '../providers/theme_provider.dart';
import '../services/equalizer_service.dart';

const List<String> kEqualizerPresets = [
  'Flat',
  'Pop',
  'Rock',
  'Classical',
  'Jazz',
  'Electronic',
  'Hip-Hop',
  'Bass Boost',
  'Vocal',
  'Custom',
];

// Per-preset band reference for the visualizer lives in the equalizer
// service; referencing the same constant keeps the DSP and the UI in sync.
const Map<String, List<double>> kPresetBands = kEqCurves;

const List<String> kBandLabels = ['60Hz', '250Hz', '1kHz', '4kHz', '16kHz'];

/// Equalizer controls: preset chips, the Custom 5-band slider bank and the
/// band visualizer. Shared by the Settings equalizer section and the
/// in-app equalizer bottom sheet (fallback when no system equalizer app
/// exists on the device).
class EqControls extends StatefulWidget {
  const EqControls({super.key});

  @override
  State<EqControls> createState() => _EqControlsState();
}

class _EqControlsState extends State<EqControls> {
  // Guard against rapid successive applies: inputs are disabled while an
  // apply is in flight.
  bool _saving = false;

  // Local mirror of the 5 custom EQ gains, so a slider drag only repaints.
  // Every pref write and platform call happens on onChangeEnd, once the
  // finger is up.
  final List<double> _eqDraft = [0, 0, 0, 0, 0];
  bool _eqDraftReady = false;
  // The preset can change from another surface (Settings sheet, backup
  // import). Track its token so the sliders follow the active DSP curve.
  String? _lastPresetToken;

  // Lazily seeds the drag draft from the persisted gains.
  List<double> _eqDraftFrom(ThemeProvider theme) {
    if (!_eqDraftReady) {
      _eqDraft
        ..clear()
        ..addAll(theme.equalizerPreset.startsWith('user:')
            ? (theme.gainsForActivePreset() ?? theme.customEqGains)
            : theme.customEqGains);
      _eqDraftReady = true;
    }
    return _eqDraft;
  }

  // Forget the draft so it is re-seeded from prefs on the next build, used
  // when the preset changes.
  void _resetEqDraft() {
    _eqDraftReady = false;
  }

  Future<void> _applyPreset(ThemeProvider theme, String preset) async {
    setState(() => _saving = true);
    try {
      await theme.setEqualizerPreset(preset);
      if (!mounted) return;
      _resetEqDraft();
      if (preset == 'Custom') {
        await EqualizerService.instance.applyCustom(theme.customEqGains);
      } else if (preset.startsWith('user:')) {
        final id = preset.substring(5);
        final index = theme.eqPresets.indexWhere((p) => p.id == id);
        if (index >= 0) {
          theme.selectEqPreset(theme.eqPresets[index]);
          await EqualizerService.instance.applyCustom(
            theme.eqPresets[index].gains,
            presetToken: preset,
          );
        }
      } else {
        await EqualizerService.instance.applyPreset(preset);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isCustomCurve(String preset) =>
      preset == 'Custom' || preset.startsWith('user:');

  Future<String?> _askPresetName(String initial) async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.eqPresetSave),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l.eqPresetName),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l.save)),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _savePreset(ThemeProvider theme) async {
    final l = AppLocalizations.of(context)!;
    final name = await _askPresetName('');
    if (name == null || !mounted) return;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.eqPresetNameEmpty)));
      return;
    }
    final index = await theme.saveEqPreset(name, _eqDraftFrom(theme));
    if (!mounted) return;
    if (index < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.eqPresetLimit)));
      return;
    }
    await EqualizerService.instance.applyCustom(
      theme.eqPresets[index].gains,
      presetToken: 'user:${theme.eqPresets[index].id}',
    );
  }

  Future<void> _presetAction(
      ThemeProvider theme, int index, String action) async {
    if (action == 'rename') {
      final name = await _askPresetName(theme.eqPresets[index].name);
      if (name == null || !mounted || name.isEmpty) return;
      await theme.renameEqPreset(index, name);
    } else {
      final wasActive = theme.equalizerPreset == 'user:${theme.eqPresets[index].id}';
      await theme.deleteEqPreset(index);
      if (!mounted) return;
      if (wasActive) {
        await EqualizerService.instance.applyPreset('Flat');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    if (_lastPresetToken != themeProvider.equalizerPreset) {
      _lastPresetToken = themeProvider.equalizerPreset;
      _resetEqDraft();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preset chips
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: kEqualizerPresets.map((preset) {
              final isSelected = preset == themeProvider.equalizerPreset;
              return ChoiceChip(
                label: Text(preset),
                selected: isSelected,
                onSelected:
                    _saving ? null : (_) => _applyPreset(themeProvider, preset),
              );
            }).toList(),
          ),
        ),
        // Custom 5-band sliders, shown for the Custom curve and for any
        // selected user preset so the curve can be inspected and tuned.
        if (_isCustomCurve(themeProvider.equalizerPreset))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: List.generate(5, (i) {
                final gains = _eqDraftFrom(themeProvider);
                return Row(
                  children: [
                    SizedBox(
                      width: 52 * MediaQuery.textScalerOf(context).scale(1.0),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(kBandLabels[i], style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: gains[i].clamp(-6.0, 6.0),
                        min: -6,
                        max: 6,
                        divisions: 24,
                        label: '${gains[i].toStringAsFixed(1)} dB',
                        // Drag only repaints: no prefs write, no platform
                        // call per frame. The service throttles and
                        // serializes applies, so even a burst of ticks could
                        // not race, but the drag should stay smooth.
                        onChanged: (v) => setState(() => gains[i] = v),
                        // Finger up: persist and commit the final curve.
                        onChangeEnd: (v) async {
                          setState(() => _saving = true);
                          try {
                            final updated = List.of(gains)..[i] = v;
                            await themeProvider.setCustomEqGains(updated);
                            await EqualizerService.instance.applyCustom(updated,
                                presetToken: themeProvider.equalizerPreset);
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: 56 * MediaQuery.textScalerOf(context).scale(1.0),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${gains[i].toStringAsFixed(1)} dB',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        // Saved named curves and the save action.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.eqPresetMyPresets,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed:
                        _saving ? null : () => _savePreset(themeProvider),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(AppLocalizations.of(context)!.eqPresetSave),
                  ),
                ],
              ),
              if (themeProvider.eqPresets.isEmpty)
                Text(
                  AppLocalizations.of(context)!.eqPresetName,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                )
              else
                Wrap(
                  spacing: 8,
                  children: List.generate(themeProvider.eqPresets.length, (i) {
                    final preset = themeProvider.eqPresets[i];
                    final selected = themeProvider.equalizerPreset ==
                        'user:${preset.id}';
                    return GestureDetector(
                      // Long-press is a shortcut to rename.
                      onLongPress: _saving
                          ? null
                          : () => _presetAction(themeProvider, i, 'rename'),
                      child: InputChip(
                        label: Text(preset.name),
                        selected: selected,
                        onPressed: _saving
                            ? null
                            : () => _applyPreset(
                                themeProvider, 'user:${preset.id}'),
                        onDeleted: _saving
                            ? null
                            : () => _presetAction(themeProvider, i, 'delete'),
                        deleteIcon: const Icon(Icons.close, size: 16),
                      ),
                    );
                  }),
                ),
            ],
          ),
        ),
        // EQ band visualizer
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: EqVisualizer(
            preset: themeProvider.equalizerPreset,
            customGains: _eqDraftFrom(themeProvider),
          ),
        ),
      ],
    );
  }
}

/// Bar display of the current curve, normalised so the largest band sets the
/// scale. Used by [EqControls].
class EqVisualizer extends StatelessWidget {
  final String preset;
  final List<double> customGains;
  const EqVisualizer(
      {super.key,
      required this.preset,
      this.customGains = const [0.0, 0.0, 0.0, 0.0, 0.0]});

  @override
  Widget build(BuildContext context) {
    final bands = (preset == 'Custom' || preset.startsWith('user:'))
        ? customGains
        : (kPresetBands[preset] ?? const [0.0, 0.0, 0.0, 0.0, 0.0]);
    final max = bands.isEmpty
        ? 0.0
        : bands.map((b) => b.abs()).reduce((a, b) => a > b ? a : b);
    final normalizer = max < 1 ? 1.0 : max;
    final color = Theme.of(context).colorScheme.primary;

    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    return Container(
      height: 80 * scale,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(bands.length, (i) {
          final gain = bands[i];
          final ratio = (gain / normalizer).clamp(-1.0, 1.0);
          final barHeight = (ratio.abs() * 32 + 4).clamp(4.0, 44.0);

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AnimatedContainer(
                duration: motionDuration(context, const Duration(milliseconds: 300)),
                curve: Curves.easeOut,
                width: 24 * scale,
                height: barHeight * scale,
                decoration: BoxDecoration(
                  color: gain > 0
                      ? color
                      : gain < 0
                          ? color.withValues(alpha: 0.4)
                          : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Text(kBandLabels[i],
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          );
        }),
      ),
    );
  }
}
