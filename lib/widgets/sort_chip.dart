import 'package:flutter/material.dart';

// Shared sort chip used by library, collections, albums and extra screens.
// Material with InkWell gives a visible ripple and a 48px tap target
// while keeping the same label style everywhere.
class SortChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final String? tooltip;
  final IconData icon;

  const SortChip({
    super.key,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.icon = Icons.sort,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tip = tooltip ?? label;
    return Material(
      color: cs.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Tooltip(
            message: tip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
