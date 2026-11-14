import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

// Per-preset band reference for the visualizer (relative gains, dB).
const Map<String, List<double>> kPresetBands = {
  'Flat': [0, 0, 0, 0, 0],
  'Pop': [1, 2, 2, 1, 0],
  'Rock': [3, 1, -1, 1, 3],
  'Classical': [2, 0, 0, 0, 2],
  'Jazz': [2, 1, 0, 1, 2],
  'Electronic': [3, 1, 0, 2, 3],
  'Hip-Hop': [3, 2, 0, 0, 1],
  'Bass Boost': [4, 3, 0, 0, 0],
  'Vocal': [-1, 0, 2, 2, 0],
  'Custom': [0, 0, 0, 0, 0],
};

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

  // Lazily seeds the drag draft from the persisted gains.
  List<double> _eqDraftFrom(ThemeProvider theme) {
    if (!_eqDraftReady) {
      _eqDraft
        ..clear()
        ..addAll(theme.customEqGains);
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
      } else {
        await EqualizerService.instance.applyPreset(preset);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
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
        // Custom 5-band sliders, shown only for the Custom preset.
        if (themeProvider.equalizerPreset == 'Custom')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: List.generate(5, (i) {
                final gains = _eqDraftFrom(themeProvider);
                return Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(kBandLabels[i], style: const TextStyle(fontSize: 12)),
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
                            await EqualizerService.instance.applyCustom(updated);
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${gains[i].toStringAsFixed(1)} dB',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                );
              }),
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
    final bands = preset == 'Custom'
        ? customGains
        : (kPresetBands[preset] ?? const [0.0, 0.0, 0.0, 0.0, 0.0]);
    final max = bands.map((b) => b.abs()).reduce((a, b) => a > b ? a : b);
    final normalizer = max < 1 ? 1.0 : max;
    final color = Theme.of(context).colorScheme.primary;

    return Container(
      height: 80,
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
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: 24,
                height: barHeight,
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
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          );
        }),
      ),
    );
  }
}
