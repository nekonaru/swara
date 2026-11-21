import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Brand palette for the launch moment: dark bamboo-panel tile with the
// yellow-to-green flute glyph, matching the launcher icon and the native
// splash screen so the cold start has no seam.
const Color _kNavy = Color(0xFF0F1A14);
// Brand accent: the pale green tip of the panpipe glyph gradient, used for the
// loader bars and the fallback icon tile.
const Color _kAccent = Color(0xFFE4F57F);
const Color _kOffWhite = Color(0xFFF6E7B8);

// Strong ease-out for entrance motion (cubic-bezier(0.23, 1, 0.32, 1)).
const Cubic _kSplashEaseOut = Cubic(0.23, 1.0, 0.32, 1.0);

// Lightweight splash shown while background init runs. The mark is painted
// at full opacity on the first frame, exactly where the native splash left it,
// so there is no blank half-second. Only the wordmark and loader animate in,
// with Fade/SlideTransitions that do not rebuild the whole tree per frame.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const double _markSide = 112.0;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _wordFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.05, 0.75, curve: _kSplashEaseOut),
  );
  late final Animation<double> _wordRise = Tween<double>(begin: 10, end: 0)
      .animate(CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.05, 0.75, curve: _kSplashEaseOut),
  ));
  late final Animation<double> _loaderFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance.isCompleted || _entrance.isAnimating) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _kNavy,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _kNavy,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final mid = constraints.maxHeight / 2;
            final markTop = mid - _markSide / 2;
            final wordTop = mid + _markSide / 2 + 20;
            final loaderTop = wordTop + 38 + 30;
            return Stack(
              fit: StackFit.expand,
              children: [
                // The mark is static and opaque from frame one: the native
                // glyph disappears and this one is already in place.
                Positioned(
                  top: markTop,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Image.asset(
                      'assets/swara-mark.png',
                      width: _markSide,
                      height: _markSide,
                      cacheWidth: 224,
                      errorBuilder: (context, _, __) => Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: _kAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Icon(Icons.music_note,
                            size: 52, color: _kAccent),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: wordTop,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FadeTransition(
                      opacity: _wordFade,
                      child: SlideTransition(
                        position: reduceMotion
                            ? const AlwaysStoppedAnimation(Offset.zero)
                            : Tween<Offset>(
                                begin: const Offset(0, 10),
                                end: Offset.zero,
                              ).animate(_wordRise),
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
                  ),
                ),
                Positioned(
                  top: loaderTop,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FadeTransition(
                      opacity: _loaderFade,
                      child: reduceMotion
                          ? Container(
                              key: const ValueKey('splash_loader_static'),
                              width: 72,
                              height: 3,
                              decoration: BoxDecoration(
                                color: _kAccent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            )
                          : const _EqualizerLoader(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Indeterminate loading indicator with the brand voice: five bars breathing
// at staggered phase offsets. Bar heights are fixed; only paint transforms
// change, so the equalizer never lays out a single pixel per frame.
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

  late final List<Animation<double>> _scales = List.generate(
    _barCount,
    (i) => Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          i / (_barCount + 1),
          (i + 1.6) / (_barCount + 1),
          curve: Curves.easeInOutSine,
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('splash_loader'),
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedBuilder(
              animation: _scales[i],
              builder: (context, child) => Transform.scale(
                scaleY: math.max(0.05, _scales[i].value),
                child: child,
              ),
              child: Container(
                width: 5,
                height: 28,
                decoration: BoxDecoration(
                  color: _kAccent,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
