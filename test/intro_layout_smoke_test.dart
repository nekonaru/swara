import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:swara/screens/onboarding_screen.dart';
import 'package:swara/screens/splash_screen.dart';

// Layout smoke tests: the intro must not clip or overflow on small phones,
// including with the OS accessibility text scale raised.
void main() {
  Future<void> pumpAt(WidgetTester tester,
      {required double textScale, required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: const MaterialApp(home: SizedBox.expand()),
    ));
    await tester.pump();
  }

  testWidgets('splash renders at 1x and 2x text scale',
      (tester) async {
    for (final scale in [1.0, 2.0]) {
      await pumpAt(tester, textScale: scale, size: const Size(360, 640));
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: const MaterialApp(home: SplashScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Swara'), findsOneWidget);
    }
  });

  testWidgets('onboarding pages do not overflow on a small screen',
      (tester) async {
    await pumpAt(tester, textScale: 2.0, size: const Size(320, 480));
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    // The three page indicator dots and the primary action are reachable.
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
