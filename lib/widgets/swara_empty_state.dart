import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/motion.dart';

/// One empty state for every list in Swara. An empty screen always says what
/// is missing and offers the next action, instead of showing a bare message.
class SwaraEmptyState extends StatelessWidget {
  const SwaraEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: title,
      child: AnimatedOpacity(
        opacity: 1,
        duration: SwaraMotion.of(context, SwaraMotion.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: SwaraSpace.lg * 2, vertical: SwaraSpace.lg + SwaraSpace.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 44, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
