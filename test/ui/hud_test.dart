import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/systems/construction.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/ui/game/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

GameController _controller() => GameController(
  world: createGame(testDefs, seed: 4),
  defs: testDefs,
);

Future<void> _pump(
  WidgetTester tester,
  GameController c, {
  Size size = const Size(1280, 720),
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: GameScreen(controller: c),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('le HUD affiche ressources, population et âge', (tester) async {
    final c = _controller();
    await _pump(tester, c);
    expect(find.text('200'), findsWidgets);
    expect(find.text('4/10'), findsOneWidget);
    expect(find.text('Âge des Villages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('centre-ville : entraîner un villageois émet la commande', (
    tester,
  ) async {
    final c = _controller();
    await _pump(tester, c);
    final tc = c.world.buildings.values.firstWhere((b) => b.owner == 0);
    c.selection.selectBuilding(tc.id);
    c.refresh();
    await tester.pump();
    expect(find.text('Centre-ville'), findsWidgets);
    final food = c.world.players[0].stock[Res.food];
    await tester.tap(find.text('Villageois').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.world.players[0].stock[Res.food], food - 50);
    expect(tc.queue, hasLength(1));
    await tester.pump();
    final queueItem = find.byIcon(Icons.close);
    expect(queueItem, findsWidgets);
    await tester.tap(queueItem.first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tc.queue, isEmpty);
    expect(c.world.players[0].stock[Res.food], food);
    expect(tester.takeException(), isNull);
  });

  testWidgets('villageois : menu de construction et pose d’une hutte', (
    tester,
  ) async {
    final c = _controller();
    await _pump(tester, c);
    final v = c.world.unitsOf(0).first;
    c.selection.selectUnits([v.id]);
    c.refresh();
    await tester.pump();
    expect(find.text('Hutte'), findsOneWidget);
    await tester.tap(find.text('Hutte'));
    await tester.pump();
    expect(c.placing?.id, 'hut');
    final p = c.world.players[0];
    final hut = testDefs.building('hut');
    var found = false;
    for (var r = 3; r < 10 && !found; r++) {
      for (var dx = -r; dx <= r && !found; dx++) {
        for (final dy in [-r, r]) {
          if (validatePlacement(
                c.world,
                0,
                hut,
                p.startX + dx,
                p.startY + dy,
              ) ==
              CmdResult.ok) {
            c.ghostX = p.startX + dx;
            c.ghostY = p.startY + dy;
            found = true;
            break;
          }
        }
      }
    }
    expect(found, isTrue);
    c.confirmPlacement();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.placing, isNull);
    expect(
      c.world.buildings.values.any((b) => b.def.id == 'hut' && b.owner == 0),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('placement invalide : refus affiché, rien n’est posé', (
    tester,
  ) async {
    final c = _controller();
    await _pump(tester, c);
    c.selection.selectUnits([c.world.unitsOf(0).first.id]);
    c.startPlacement(testDefs.building('hut'));
    c.ghostX = 0;
    c.ghostY = 0;
    c.world.players[0].explored.fillRange(0, c.world.map.size, 0);
    c.confirmPlacement();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.lastRejection, 'badPlacement');
    expect(find.text('Emplacement impossible'), findsOneWidget);
    expect(c.world.buildings.values.where((b) => b.def.id == 'hut'), isEmpty);
  });

  testWidgets('suppression : confirmation obligatoire, partie en pause', (
    tester,
  ) async {
    final c = _controller();
    await _pump(tester, c);
    final p = c.world.players[0];
    final hut = c.world.spawnBuilding(
      testDefs.building('hut'),
      0,
      p.startX + 6,
      p.startY,
      complete: true,
    );
    c.selection.selectBuilding(hut.id);
    c.refresh();
    await tester.pump();
    await tester.tap(find.text('Supprimer'));
    await tester.pump();
    expect(find.text('Supprimer ce bâtiment ?'), findsOneWidget);
    expect(c.loop.paused, isTrue);
    await tester.tap(find.text('Annuler').last);
    await tester.pump();
    expect(c.world.buildings.containsKey(hut.id), isTrue);
    expect(c.loop.paused, isFalse);
    c.selection.selectBuilding(hut.id);
    c.refresh();
    await tester.pump();
    await tester.tap(find.text('Supprimer'));
    await tester.pump();
    await tester.tap(find.text('Confirmer'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.world.buildings.containsKey(hut.id), isFalse);
  });

  testWidgets('menu pause : Reprendre relance la partie', (tester) async {
    final c = _controller();
    await _pump(tester, c);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    expect(c.loop.paused, isTrue);
    expect(find.text('Menu'), findsWidgets);
    await tester.tap(find.text('Reprendre'));
    await tester.pump();
    expect(c.loop.paused, isFalse);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(c.loop.paused, isTrue);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.tap(find.text('×1'));
    await tester.pump();
    expect(c.loop.speed, 1.5);
  });

  testWidgets('arrière-plan : pause auto, jamais de reprise automatique', (
    tester,
  ) async {
    final c = _controller();
    await _pump(tester, c);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(c.loop.pauseReasons, contains(PauseReason.lifecycle));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(c.loop.paused, isTrue, reason: 'écran de reprise');
    expect(find.text('Partie en pause'), findsOneWidget);
  });

  testWidgets('villageois inactifs : compteur et bouton', (tester) async {
    final c = _controller();
    await _pump(tester, c);
    expect(c.idleVillagerCount, 4);
    expect(find.text('4'), findsWidgets);
    await tester.tap(find.byIcon(Icons.person_off));
    await tester.pump();
    expect(c.selection.units, hasLength(1));
    for (final u in c.world.unitsOf(0)) {
      expect(u.state, UnitState.idle);
    }
  });

  group('goldens du HUD', () {
    const sizes = <String, Size>{
      '854x400': Size(854, 400),
      '1280x720': Size(1280, 720),
      '2560x1080': Size(2560, 1080),
    };
    for (final e in sizes.entries) {
      testWidgets('HUD ${e.key} (centre-ville sélectionné)', tags: ['golden'], (
        tester,
      ) async {
        final c = _controller();
        await _pump(tester, c, size: e.value);
        final tc = c.world.buildings.values.firstWhere((b) => b.owner == 0);
        c.selection.selectBuilding(tc.id);
        c.world.players[0].stock[Res.food] = 345;
        c.refresh();
        await tester.pump(const Duration(milliseconds: 50));
        await expectLater(
          find.byType(GameScreen),
          matchesGoldenFile('goldens/hud_${e.key}.png'),
        );
      });
    }
  });

  group('responsive : aucun débordement', () {
    const sizes = <String, Size>{
      '360x800': Size(360, 800),
      '412x915': Size(412, 915),
      '800x1280': Size(800, 1280),
      '1280x720': Size(1280, 720),
      '1920x1080': Size(1920, 1080),
      '2560x1080': Size(2560, 1080),
      '854x400 (téléphone paysage)': Size(854, 400),
      '1024x576 (taille mini PC)': Size(1024, 576),
    };
    for (final e in sizes.entries) {
      for (final scale in const [0.8, 1.0, 1.5]) {
        testWidgets('${e.key} à l’échelle $scale', (tester) async {
          final c = _controller();
          await _pump(tester, c, size: e.value, scale: scale);
          final tc = c.world.buildings.values.firstWhere((b) => b.owner == 0);
          c.selection.selectBuilding(tc.id);
          c.refresh();
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'bâtiment');
          c.selection.selectUnits(c.world.unitsOf(0).map((u) => u.id));
          c.refresh();
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'villageois');
          final first = c.world.unitsOf(0).first;
          final s = c.world.spawnUnit(
            testDefs.unit('spearman'),
            0,
            first.x,
            first.y,
          );
          c.selection.selectUnits([s.id]);
          c.refresh();
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'soldat');
        });
      }
    }
  });
}
