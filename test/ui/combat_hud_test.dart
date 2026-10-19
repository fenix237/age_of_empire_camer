import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/systems/victory.dart';
import 'package:age_of_empire_camer/ui/game/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';
import '../helpers/test_defs.dart';

GameController _controller({int victory = VictoryMode.none}) => GameController(
  world: createGame(testDefs, seed: 4, victoryMode: victory),
  defs: testDefs,
);

Future<void> _pump(WidgetTester tester, GameController c) async {
  await tester.binding.setSurfaceSize(const Size(1280, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        closeCoordinatorProvider.overrideWithValue(
          CloseCoordinator(terminate: () async {}),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: GameScreen(controller: c),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('le panneau de combat affiche tambour, sorts et âge suivant', (
    tester,
  ) async {
    final c = _controller();
    await _pump(tester, c);
    expect(find.text('Énergie du tambour'), findsOneWidget);
    expect(find.text('Foudre'), findsOneWidget);
    expect(find.textContaining('Âge suivant'), findsOneWidget);
    expect(find.text('F5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pouvoirs de l’unité sélectionnée : bouton et ciblage', (
    tester,
  ) async {
    final c = _controller();
    final u = addUnit(c.world, 'archer', 10, 10);
    c.world.players[0].age = 1;
    c.selection.selectUnits(<int>[u.id]);
    await _pump(tester, c);
    c.refresh();
    await tester.pump();
    expect(find.text('Pluie de flèches'), findsOneWidget);
    await tester.tap(find.text('Pluie de flèches'));
    await tester.pump();
    expect(c.targeting, isNotNull);
    expect(find.textContaining('touchez la cible'), findsOneWidget);
    c.cancelTargeting();
    await tester.pump();
    expect(find.textContaining('touchez la cible'), findsNothing);
  });

  testWidgets('écran de fin : défaite affichée avec les statistiques', (
    tester,
  ) async {
    final c = _controller(victory: VictoryMode.conquest);
    await _pump(tester, c);
    c.resign();
    for (var i = 0; i < 30; i++) {
      c.world.step();
    }
    c.refresh();
    await tester.pump();
    await tester.pump();
    expect(find.text('Défaite'), findsOneWidget);
    expect(find.text('Unités ennemies tuées'), findsOneWidget);
    expect(find.text('Quitter vers le menu'), findsWidgets);
    // Partie terminée : seule la sortie est proposée.
    expect(find.text('Continuer à regarder'), findsNothing);
  });
}
