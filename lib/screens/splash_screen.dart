import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Brand palette for the launch moment: deep navy tile with the azure wave,
// matching the launcher icon and the native splash screen so the cold start
// has no seam.
const Color _kNavy = Color(0xFF0A1830);
const Color _kAzure = Color(0xFF2E6BFF);
const Color _kOffWhite = Color(0xFFF5F3EE);

// Strong ease-out for entrance motion (cubic-bezier(0.23, 1, 0.32, 1)).
const Cubic _kSplashEaseOut = Cubic(0.23, 1.0, 0.32, 1.0);

// Lightweight splash shown while background init runs. The native splash and
// this screen share one background, so the handoff is invisible; the mark,
// wordmark and equalizer loader fade and rise in a short choreographed
// entrance. Reduced motion gets opacity only, no movement.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  // Mark enters first: fades in while scaling from 0.88. Never scale(0).
  late final Animation<double> _markFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.72, curve: _kSplashEaseOut),
  );
  late final Animation<double> _markScale = Tween<double>(
    begin: 0.88,
    end: 1.0,
  ).animate(CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.72, curve: _kSplashEaseOut),
  ));

  // Wordmark follows the mark, ~140 ms behind it, fading and rising.
  late final Animation<double> _wordFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.2, 0.92, curve: _kSplashEaseOut),
  );
  late final Animation<double> _wordRise = Tween<double>(
    begin: 10,
    end: 0,
  ).animate(CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.2, 0.92, curve: _kSplashEaseOut),
  ));

  // Loader fades in last; it loops while boot init finishes.
  late final Animation<double> _loaderFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final reduceMotion = disableAnimations;

    // Status and navigation bars match the splash so the whole cold start
    // reads as one surface instead of stacked chromes.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kNavy,
        body: Center(
          key: const ValueKey('splash_content'),
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, _) {
              final markFade = _markFade.value;
              final wordFade = _wordFade.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: markFade,
                    child: Transform.scale(
                      scale: reduceMotion ? 1.0 : _markScale.value,
                      child: Image.asset(
                        'assets/swara-mark.png',
                        width: 112,
                        height: 112,
                        // Decode at display size instead of the full resolution.
                        cacheWidth: 224,
                        errorBuilder: (context, _, __) => Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: _kAzure.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: const Icon(
                            Icons.music_note,
                            size: 52,
                            color: _kAzure,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Opacity(
                    opacity: wordFade,
                    child: Transform.translate(
                      offset: reduceMotion
                          ? Offset.zero
                          : Offset(0, _wordRise.value),
                      child: const Text(
                        'Swara',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: _kOffWhite,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Opacity(
                    opacity: _loaderFade.value,
                    child: reduceMotion
                        ? Container(
                            key: const ValueKey('splash_loader_static'),
                            width: 72,
                            height: 3,
                            decoration: BoxDecoration(
                              color: _kAzure,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )
                        : const _EqualizerLoader(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// Indeterminate loading indicator with the brand voice: five azure bars
// breathing at staggered phase offsets, like a low-latency equalizer.
// Runs only while the splash is visible; disposed with it.
class _EqualizerLoader extends StatefulWidget {
  const _EqualizerLoader();

  @override
  State<_EqualizerLoader> createState() => _EqualizerLoaderState();
}

class _EqualizerLoaderState extends State<_EqualizerLoader>
    with SingleTickerProviderStateMixin {
  static const int _barCount = 5;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        return SizedBox(
          key: const ValueKey('splash_loader'),
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_barCount, (i) {
              // Each bar breathes on its own phase offset so the set reads
              // as music, not as a row of identical pulses.
              final phase = i * 0.9;
              final wave = math.sin(t + phase);
              final normalized = (wave + 1) / 2; // 0..1
              final height = 6 + normalized * 22;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: 5,
                  height: height,
                  decoration: BoxDecoration(
                    color: _kAzure,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
