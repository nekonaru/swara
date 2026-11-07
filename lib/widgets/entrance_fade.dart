import 'package:flutter/material.dart';

/// One-shot entrance fade for list rows and grid cells.
///
/// Only the first [animateUpTo] items animate; the rest render static, so a
/// 20k row list never schedules hundreds of simultaneous opacity layers on
/// its first layout. The duration staggers slightly by index inside that
/// cap to keep the cascade feel of the original per row animation.
class EntranceFade extends StatelessWidget {
  final int index;
  final Widget child;

  const EntranceFade({super.key, required this.index, required this.child});

  static const int animateUpTo = 12;

  @override
  Widget build(BuildContext context) {
    if (index >= animateUpTo) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 160 + (index % 10) * 20),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 6),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
