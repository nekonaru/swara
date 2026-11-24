import 'package:flutter/material.dart';
import '../utils/motion.dart';

/// "Now playing" indicator with 3 animated bars moving up and down,
/// placed next to the active song in lists.
class PlayingIndicator extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  const PlayingIndicator({super.key, required this.isPlaying, required this.color});

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = reduceMotion(context);
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    for (final c in _controllers) {
      if (reduced) {
        c
          ..stop()
          ..reset();
      } else if (widget.isPlaying) {
        c.repeat(reverse: true);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Start the bars only when something is actually playing, so idle
    // rows never pay for the animation ticker.
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 450 + i * 120),
      ),
    );
    if (widget.isPlaying) {
      for (final c in _controllers) {
        c.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(covariant PlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying == oldWidget.isPlaying) return;
    for (final c in _controllers) {
      if (_reducedMotion) {
        c
          ..stop()
          ..reset();
      } else if (widget.isPlaying) {
        // Always restart on a false-to-true transition: a pause animation
        // may still be running and isAnimating would skip the restart.
        c.stop();
        c.repeat(reverse: true);
      } else {
        c.animateTo(0.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _controllers.map((c) {
          return AnimatedBuilder(
            animation: c,
            builder: (context, _) => Container(
              width: 3,
              height: 4 + (c.value * 14),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
