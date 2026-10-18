import 'dart:io';

import 'package:age_of_empire_camer/app/app.dart';
import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/app/window/window_service.dart';
import 'package:age_of_empire_camer/meta/save_store.dart';
import 'package:age_of_empire_camer/ui/game/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Laisse les entrées/sorties réelles (fichiers) se terminer : chaque `await`
/// d'E/S exige une alternance « temps réel » / « microtâches simulées ».
Future<void> _io(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets(
    'menu → nouvelle partie → jeu → sauvegarde → menu → reprendre',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('rdf_flow');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = SaveStore(dir);
      tester.view
        ..physicalSize = const Size(1280, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: <Override>[
          closeCoordinatorProvider.overrideWithValue(
            CloseCoordinator(terminate: () async {}),
          ),
          windowServiceProvider.overrideWithValue(NoopWindowService()),
          saveStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const App()),
      );
      await tester.pumpAndSettle();

      // « Reprendre » désactivé sans sauvegarde.
      final resume = find.widgetWithText(FilledButton, 'Reprendre la partie');
      expect(tester.widget<FilledButton>(resume).onPressed, isNull);

      await tester.tap(find.text('Nouvelle partie'));
      await tester.pumpAndSettle();
      expect(find.text('Graine de la carte'), findsOneWidget);
      await tester.tap(find.text('Jouer'));
      await tester.pump(const Duration(milliseconds: 200));
      await _io(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.text('4/10'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // La partie avance (ticks de simulation).
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Menu → Sauvegarder.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.tap(find.text('Sauvegarder'));
      await tester.pump();
      await _io(tester);
      expect(store.exists('quicksave'), isTrue);

      // Quitter vers le menu : tout est sauvegardé, pas de question.
      await tester.tap(find.text('Quitter vers le menu'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle partie'), findsOneWidget);

      // Reprendre charge la sauvegarde.
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
      await tester.tap(resume);
      await tester.pump(const Duration(milliseconds: 200));
      await _io(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.text('4/10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
