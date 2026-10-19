import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/meta/campaign_progress.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_setup.dart';
import 'package:age_of_empire_camer/sim/systems/combat.dart';
import 'package:age_of_empire_camer/ui/campaign/campaign_screen.dart';
import 'package:age_of_empire_camer/ui/game/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';
import '../sim/campaign_test.dart' show campaign;

Future<ProviderContainer> _pump(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      closeCoordinatorProvider.overrideWithValue(
        CloseCoordinator(terminate: () async {}),
      ),
      campaignProvider.overrideWith((ref) async => campaign),
      defsProvider.overrideWith((ref) async => testDefs),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

void main() {
  testWidgets('carte du royaume : seule la mission 1 est ouverte', (
    tester,
  ) async {
    final c = await _pump(tester, const CampaignScreen());
    expect(find.text('Les premiers feux'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNWidgets(6));
    // Mission verrouillée : aucun briefing.
    await tester.tap(find.byIcon(Icons.lock).first, warnIfMissed: false);
    await tester.pump();
    expect(find.text('Commencer'), findsNothing);
    // Mission 1 : briefing avec difficulté.
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('1. Les premiers feux'), findsOneWidget);
    expect(find.text('Difficulté'), findsOneWidget);
    expect(find.textContaining('Entraîner 3 villageois'), findsOneWidget);
    expect(
      find.textContaining('Bâtir une hutte'),
      findsNothing,
      reason: 'objectif masqué',
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(c.read(progressProvider).totalStars(), 0);
  });

  testWidgets('la mission réussie ouvre la suivante', (tester) async {
    final c = await _pump(tester, const CampaignScreen());
    final m1 = campaign.byId('m1')!;
    c
        .read(progressProvider.notifier)
        .update(
          c
              .read(progressProvider)
              .withWin(
                m1,
                stars: 3,
                seconds: 600,
                difficulty: 1,
                ending: '',
              ),
        );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsNWidgets(5));
    expect(c.read(progressProvider).unlocked(campaign), contains('tower'));
  });

  testWidgets('dialogue d’intro : partie en pause jusqu’à la fermeture', (
    tester,
  ) async {
    final w = createMissionGame(testDefs, campaign.byId('m1')!);
    final ctl = GameController(world: w, defs: testDefs);
    await _pump(tester, GameScreen(controller: ctl));
    for (var i = 0; i < 12; i++) {
      w.step();
    }
    ctl.refresh();
    await tester.pump();
    await tester.pump();
    expect(find.text('Mbarga'), findsWidgets);
    expect(ctl.loop.pauseReasons, contains(PauseReason.dialog));
    expect(find.text('Suite'), findsOneWidget);
    await tester.tap(find.text('Suite'));
    await tester.pump();
    expect(find.text('Fermer'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pump();
    await tester.pump();
    expect(ctl.loop.pauseReasons, isNot(contains(PauseReason.dialog)));
    expect(w.mission!.dialogs, isEmpty);
    // Objectifs et aide du tutoriel affichés.
    expect(find.textContaining('Entraîner 3 villageois'), findsOneWidget);
    expect(find.textContaining('Cliquez sur le centre-ville'), findsOneWidget);
  });

  testWidgets('fin de mission : victoire enregistrée avec étoiles', (
    tester,
  ) async {
    final w = createMissionGame(testDefs, campaign.byId('m6')!);
    final ctl = GameController(world: w, defs: testDefs);
    final c = await _pump(tester, GameScreen(controller: ctl));
    for (var i = 0; i < 12; i++) {
      w.step();
    }
    w.mission!.dialogs.clear();
    for (final id in w.mission!.tags['enemy_army']!) {
      final u = w.units[id];
      if (u != null) damageUnit(w, u, 9999, srcOwner: 0);
    }
    final tc = w.buildings.values.firstWhere(
      (b) => b.owner == 1 && b.def.townCenter,
    );
    damageBuilding(w, tc, 999999, srcOwner: 0);
    for (var i = 0; i < 60 && w.mission!.running; i++) {
      w.step();
    }
    expect(w.mission!.won, isTrue);
    ctl.refresh();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Victoire !'), findsOneWidget);
    expect(find.text('Carte du royaume'), findsOneWidget);
    expect(c.read(progressProvider).isDone('m6'), isTrue);
    expect(c.read(progressProvider).missions['m6']!.stars, w.mission!.stars);
    expect(find.textContaining('Débloqué'), findsOneWidget);
  });

  test('progression : meilleur résultat conservé, défi du jour', () {
    final m = campaign.byId('m2')!;
    var p = const CampaignProgress()
        .withWin(m, stars: 2, seconds: 500, difficulty: 1, ending: '')
        .withWin(m, stars: 1, seconds: 400, difficulty: 0, ending: '');
    expect(p.missions['m2']!.stars, 2);
    expect(p.missions['m2']!.bestSeconds, 400);
    expect(p.missions['m2']!.difficulty, 1);
    p = p.withDaily('2026-10-19', 900).withDaily('2026-10-19', 1200);
    expect(p.daily['2026-10-19'], 900);
    final back = CampaignProgress.fromJson(p.toJson());
    expect(back.missions['m2']!.bestSeconds, 400);
    expect(back.daily['2026-10-19'], 900);
    expect(back.isAvailable(campaign.byId('m3')!), isTrue);
    expect(back.isAvailable(campaign.byId('m4')!), isFalse);
  });
}
