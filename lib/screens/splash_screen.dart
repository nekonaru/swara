import 'package:flutter/material.dart';

// Lightweight splash shown while background init runs.
// Keeps only the app name so no localization lookup is needed here.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Brand mark asset (transparent, theme independent).
            Image.asset(
              'assets/swara-mark.png',
              width: 96,
              height: 96,
              // Decode at display size instead of the full resolution.
              cacheWidth: 192,
              errorBuilder: (context, _, __) => Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.music_note,
                  size: 48,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Swara',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
