import 'package:flutter/widgets.dart';

/// One source of truth for the OS "reduce animations" setting. Every Swara
/// entrance, page change and loader consults this so accessibility preferences
/// are honoured consistently instead of per screen.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Shared duration helper so every animated widget can honour the OS
/// "remove animations" setting without duplicating the check.
Duration motionDuration(BuildContext context, Duration duration) =>
    reduceMotion(context) ? Duration.zero : duration;

/// Shared motion vocabulary. Durations stay short so the UI answers the
/// finger immediately, and the curve is always decelerating: nothing in a
/// music player should bounce after the user has already decided.
abstract final class SwaraMotion {
  static const Duration feedback = Duration(milliseconds: 120);
  static const Duration small = Duration(milliseconds: 220);
  static const Duration page = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, Duration duration) =>
      motionDuration(context, duration);

  static Curve curveOf(BuildContext context) =>
      reduceMotion(context) ? Curves.linear : curve;
}
