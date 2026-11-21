import 'package:flutter/widgets.dart';

/// One source of truth for the OS "reduce animations" setting. Every Swara
/// entrance, page change and loader consults this so accessibility preferences
/// are honoured consistently instead of per screen.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
