import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/systems/victory.dart';
import 'package:age_of_empire_camer/ui/menu/new_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';
import '../helpers/test_defs.dart';

void main() {
  test('réglages : humain d’abord, IA avec des clans différents', () {
    const o = NewGameOptions(seed: 7, clan: 1, aiCount: 3, difficulty: 2);
    final s = skirmishSetups(testDefs, o);
    expect(s, hasLength(4));
    expect(s.first.aiLevel, -1);
    expect(s.first.clan, 1);
    expect(s.skip(1).every((e) => e.aiLevel == 2), isTrue);
    expect(s.skip(1).map((e) => e.clan).toSet(), hasLength(3));
    expect(s.skip(1).any((e) => e.clan == 1), isFalse);
  });

  test('spectateur : que des IA, au moins deux', () {
    const o = NewGameOptions(spectator: true);
    expect(o.players, 2);
    final s = skirmishSetups(testDefs, o);
    expect(s.every((e) => e.aiLevel >= 0), isTrue);
  });

  test('une partie lancée depuis le menu se déroule sans violation', () {
    const o = NewGameOptions(
      seed: 3,
      aiCount: 2,
      resourcePercent: 200,
      victory: VictoryMode.townCenters,
    );
    final w = createGame(
      testDefs,
      seed: o.seed,
      players: o.players,
      setups: skirmishSetups(testDefs, o),
      startingResources: testDefs.balance.startingResources.scaled(200, 100),
      victoryMode: o.victory,
    );
    expect(w.players[0].stock.v.first, greaterThan(300));
    run(w, 600);
    expectHealthy(w);
  });

  testWidgets('le menu affiche le bonus de l’IA Difficile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NewGameOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<NewGameOptions>(
                context: context,
                builder: (_) => SkirmishDialog(defs: testDefs),
              );
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Escarmouche'), findsOneWidget);
    expect(find.textContaining('Bonus de l’IA'), findsNothing);
    await tester.ensureVisible(find.text('Difficile'));
    await tester.pump();
    await tester.tap(find.text('Difficile'));
    await tester.pump();
    expect(find.textContaining('Bonus de l’IA : +25 %'), findsOneWidget);
    await tester.ensureVisible(find.text('Jouer'));
    await tester.tap(find.text('Jouer'));
    await tester.pumpAndSettle();
    expect(result?.difficulty, 2);
  });
}
