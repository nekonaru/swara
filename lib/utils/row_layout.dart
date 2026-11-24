import 'package:flutter/widgets.dart';

/// Row height that follows the effective text scale. Fixed extents must grow
/// with accessibility text, otherwise large text is clipped or silently
/// scaled down.
double scaledRowHeight(BuildContext context, double base) {
  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
  return base * scale.clamp(1.0, 2.0);
}
