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
