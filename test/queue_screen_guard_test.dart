import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:swara/screens/queue_screen.dart';
import 'package:swara/services/player_service.dart';

// Regression guard for the v3.6.0 queue screen: it used a Selector without a
// provider ancestor for PlayerService, which threw ProviderNotFoundException
// and showed an empty grey screen in release builds. The smoke test below
// builds the screen the same way the app does (global provider).
void main() {
  testWidgets('QueueScreen builds without a provider lookup failure',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: PlayerService.instance),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QueueScreen(),
        ),
      ),
    );
    await tester.pump();

    // No exception rendered; the empty queue state is visible.
    expect(tester.takeException(), isNull);
    expect(find.byType(QueueScreen), findsOneWidget);
  });

  test('PlayerService is registered in the app provider tree', () {
    // Selector<PlayerService> crashes with ProviderNotFoundException when no
    // ancestor provides the singleton. The app registers it in main.dart;
    // keep that pinned so a refactor cannot remove it silently.
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main.contains('ChangeNotifierProvider.value(value: PlayerService.instance)'),
      isTrue,
      reason: 'PlayerService must stay registered in the app provider tree',
    );
  });
}
