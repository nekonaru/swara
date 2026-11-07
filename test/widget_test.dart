import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:swara/screens/splash_screen.dart';

// Smoke test: the splash screen renders its brand mark and name without
// needing the database or any platform channel.
void main() {
  testWidgets('SplashScreen renders the brand mark', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Swara'), findsOneWidget);
  });
}
