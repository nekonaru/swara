import 'package:flutter/material.dart';

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
    for (final c in _controllers) {
      if (widget.isPlaying) {
        if (!c.isAnimating) c.repeat(reverse: true);
      } else {
        // Settle at the baseline over a short curve instead of freezing
        // mid-bounce and snapping when playback pauses.
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
