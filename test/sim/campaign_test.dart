import 'dart:convert';
import 'dart:io';

import 'package:age_of_empire_camer/sim/campaign/mission_def.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_runtime.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_setup.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_validator.dart';
import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/save/save_codec.dart';
import 'package:age_of_empire_camer/sim/systems/combat.dart';
import 'package:age_of_empire_camer/sim/systems/construction.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';
import '../helpers/test_defs.dart';

final CampaignDef campaign = CampaignDef.fromString(
  File('assets/campaign/campaign.json').readAsStringSync(),
);

World start(String id, {int difficulty = 1, Set<String> unlocked = const {}}) {
  final w = createMissionGame(
    testDefs,
    campaign.byId(id)!,
    difficulty: difficulty,
    unlocked: unlocked,
  )..checkInvariantsEachTick = true;
  return w;
}

Building tc(World w, [int owner = 0]) => w.buildings.values.firstWhere(
  (b) => b.owner == owner && b.def.townCenter,
);

/// Case de pose valide la plus proche pour un bâtiment du joueur 0.
({int x, int y}) spot(World w, String id, int nearX, int nearY) {
  final def = testDefs.building(id);
  for (var r = 2; r < 25; r++) {
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        if (dx.abs() != r && dy.abs() != r) continue;
        if (validatePlacement(w, 0, def, nearX + dx, nearY + dy) ==
            CmdResult.ok) {
          return (x: nearX + dx, y: nearY + dy);
        }
      }
    }
  }
  fail('aucune case pour $id');
}

List<Unit> mine(World w, {String? id, int owner = 0}) => <Unit>[
  for (final u in w.units.values)
    if (u.owner == owner && u.alive && (id == null || u.def.id == id)) u,
];

List<Unit> tagged(World w, String tag) => <Unit>[
  for (final id in w.mission!.tags[tag] ?? const <int>[])
    if (w.units[id] != null && w.units[id]!.alive) w.units[id]!,
];

void teleport(World w, Unit u, int x, int y) {
  final free = freeTileNear(w, x, y, <int>{})!;
  final tx = free.$1;
  final ty = free.$2;
  u
    ..x = Fx.tileCenter(tx)
    ..y = Fx.tileCenter(ty)
    ..px = Fx.tileCenter(tx)
    ..py = Fx.tileCenter(ty)
    ..clearPath();
  w.setState(u, UnitState.idle);
  u.orders.clear();
}

/// Renfort de soldats puissants autour de (x, y).
void guard(World w, int x, int y, {int n = 16, int owner = 0}) {
  final used = <int>{};
  for (var i = 0; i < n; i++) {
    final t = freeTileNear(w, x, y, used)!;
    used.add(w.map.index(t.$1, t.$2));
    addUnit(w, 'iron_warrior', t.$1, t.$2, owner: owner);
  }
}

void main() {
  group('lecture des données', () {
    test('la campagne se charge : 7 missions chaînées', () {
      expect(campaign.missions, hasLength(7));
      expect(campaign.missions.first.requires, isEmpty);
      for (final m in campaign.missions.skip(1)) {
        expect(m.requires, hasLength(1));
        expect(campaign.byId(m.requires.single), isNotNull);
      }
    });

    Map<String, dynamic> raw() =>
        jsonDecode(File('assets/campaign/campaign.json').readAsStringSync())
            as Map<String, dynamic>;

    test('une condition inconnue est refusée avec son chemin', () {
      final j = raw();
      final m = (j['missions'] as List<dynamic>).first as Map<String, dynamic>;
      ((m['objectives'] as List<dynamic>).first
          as Map<String, dynamic>)['done'] = <String, dynamic>{
        'kind': 'teleport',
      };
      expect(
        () => CampaignDef.fromJson(j),
        throwsA(
          isA<DataException>().having(
            (e) => e.path,
            'path',
            contains(r'$.missions[0].objectives[0].done'),
          ),
        ),
      );
    });

    test('le validateur détecte unités inconnues, étiquettes orphelines…', () {
      final j = raw();
      final ms = j['missions'] as List<dynamic>;
      final m2 = ms[1] as Map<String, dynamic>;
      ((m2['placements'] as List<dynamic>).first
              as Map<String, dynamic>)['unit'] =
          'dragon';
      ((m2['objectives'] as List<dynamic>)[1] as Map<String, dynamic>)['done'] =
          <String, dynamic>{'kind': 'no_units', 'owner': 1, 'tag': 'fantomes'};
      final m4 = ms[3] as Map<String, dynamic>;
      ((m4['objectives'] as List<dynamic>)[1]
          as Map<String, dynamic>)['done'] = <String, dynamic>{
        'kind': 'gather',
        'res': 'iron',
        'amount': 99999999,
      };
      final problems = validateCampaign(testDefs, CampaignDef.fromJson(j));
      expect(
        problems.any((p) => p.contains('dragon')),
        isTrue,
        reason: '$problems',
      );
      expect(problems.any((p) => p.contains('fantomes')), isTrue);
    });

    test('le validateur détecte une récolte impossible sur la carte', () {
      final j = raw();
      final m4 = (j['missions'] as List<dynamic>)[3] as Map<String, dynamic>;
      ((m4['objectives'] as List<dynamic>)[1]
          as Map<String, dynamic>)['done'] = <String, dynamic>{
        'kind': 'gather',
        'res': 'iron',
        'amount': 99999999,
      };
      final problems = validateCampaign(testDefs, CampaignDef.fromJson(j));
      expect(
        problems.any((p) => p.contains('seulement')),
        isTrue,
        reason: '$problems',
      );
    });

    test('un objectif masqué jamais révélé est signalé', () {
      final j = raw();
      final m1 = (j['missions'] as List<dynamic>).first as Map<String, dynamic>;
      (m1['triggers'] as List<dynamic>).removeWhere(
        (t) => (t as Map<String, dynamic>)['id'] == 't_hut',
      );
      final problems = validateCampaign(testDefs, CampaignDef.fromJson(j));
      expect(problems.any((p) => p.contains('jamais révélé')), isTrue);
    });
  });

  group('création et déblocages', () {
    test('verrous : bâtiment interdit tant que non débloqué', () {
      final w = start('m1');
      w.players[0].age = 1;
      final b = spot(w, 'hut', tc(w).tx, tc(w).ty);
      final villager = mine(w, id: 'villager').first;
      expect(
        BuildCmd(0, [villager.id], 'tower', b.x, b.y).apply(w),
        CmdResult.locked,
      );
      final w2 = start('m1', unlocked: {'tower'});
      final b2 = spot(w2, 'hut', tc(w2).tx, tc(w2).ty);
      w2.players[0]
        ..age = 1
        ..stock[Res.stone] = 200;
      expect(
        BuildCmd(
          0,
          [mine(w2, id: 'villager').first.id],
          'tower',
          b2.x,
          b2.y,
        ).apply(w2),
        CmdResult.ok,
      );
    });

    test('difficulté : effectifs des vagues et ressources', () {
      final easy = start('m2', difficulty: 0);
      final hard = start('m2', difficulty: 2);
      expect(
        easy.players[0].stock.v.first,
        greaterThan(hard.players[0].stock.v.first),
      );
      run(easy, 905);
      run(hard, 905);
      expect(
        tagged(hard, 'raiders').length,
        greaterThan(tagged(easy, 'raiders').length),
      );
    });

    test('étiquettes et entités posées existent à la création', () {
      final w = start('m7');
      expect(tagged(w, 'mine'), hasLength(17));
      expect(w.mission!.tags['fortress'], hasLength(1));
      expect(
        w.buildings.containsKey(w.mission!.tags['fortress']!.first),
        isTrue,
      );
      expect(w.mission!.tags['towers'], hasLength(3));
    });
  });

  group('missions de bout en bout', () {
    test('M1 (tutoriel) : accomplie avec de vraies commandes', () {
      final w = start('m1');
      final m = w.mission!;
      final center = tc(w);
      expect(m.visibleObjectives.map((o) => o.id), ['villagers']);
      expect(m.dialogs, isEmpty);
      run(w, 10);
      expect(m.dialogs, hasLength(1));
      expect(m.hint, contains('centre-ville'));

      // 1. Trois villageois.
      w.submit(TrainCmd(0, center.id, 'villager', count: 3));
      runUntil(
        w,
        () => m.objectiveState('villagers') == ObjState.done,
        limit: 1500,
        why: 'villageois',
      );
      run(w, 10);
      expect(m.objectiveState('hut'), ObjState.active);

      // 2. Une hutte.
      final workers = mine(w, id: 'villager');
      final hut = spot(w, 'hut', center.tx + 5, center.ty);
      w.submit(
        BuildCmd(0, [workers[0].id, workers[1].id], 'hut', hut.x, hut.y),
      );
      runUntil(
        w,
        () => m.objectiveState('hut') == ObjState.done,
        limit: 2500,
        why: 'hutte',
      );
      run(w, 10);

      // 3. Du bois.
      final tree = w.nodes.values.where((n) => n.def.id == 'tree').reduce((
        a,
        b,
      ) {
        int d(ResourceNode n) =>
            (n.tx - center.tx) * (n.tx - center.tx) +
            (n.ty - center.ty) * (n.ty - center.ty);
        return d(a) <= d(b) ? a : b;
      });
      w.submit(GatherCmd(0, [for (final u in workers) u.id], tree.id));
      runUntil(
        w,
        () => m.objectiveState('wood') == ObjState.done,
        limit: 9000,
        why: 'bois',
      );
      run(w, 10);
      expect(m.objectiveState('field'), ObjState.active);

      // 4. Un champ, 5. une caserne.
      final field = spot(w, 'field', center.tx - 4, center.ty + 4);
      w.submit(
        BuildCmd(
          0,
          [for (final u in workers.take(3)) u.id],
          'field',
          field.x,
          field.y,
        ),
      );
      runUntil(
        w,
        () => m.objectiveState('field') == ObjState.done,
        why: 'champ',
      );
      run(w, 10);
      final bar = spot(w, 'barracks', center.tx + 8, center.ty - 6);
      w.submit(
        BuildCmd(
          0,
          [for (final u in workers.take(4)) u.id],
          'barracks',
          bar.x,
          bar.y,
        ),
      );
      runUntil(
        w,
        () => m.objectiveState('barracks') == ObjState.done,
        limit: 4000,
        why: 'caserne',
      );
      run(w, 10);

      // 6. Trois lanciers.
      final barracks = w.buildings.values.firstWhere(
        (b) => b.owner == 0 && b.def.id == 'barracks',
      );
      w.submit(TrainCmd(0, barracks.id, 'spearman', count: 3));
      runUntil(
        w,
        () => m.status != MissionStatus.running,
        limit: 4000,
        why: 'lanciers',
      );
      expect(m.won, isTrue);
      expect(w.gameOver, isTrue);
      expect(w.winnerTeam, w.players[0].team);
      expect(m.stars, inInclusiveRange(1, 3));
      expect(w.violations, isEmpty);
    });

    test('M2 : survivre 7 minutes aux quatre vagues', () {
      final w = start('m2');
      final m = w.mission!;
      final c = tc(w);
      guard(w, c.tx + 3, c.ty + 3, n: 24);
      runUntil(w, () => m.status != MissionStatus.running, limit: 4400);
      expect(m.won, isTrue, reason: 'statut ${m.status}');
      expect(w.tick ~/ 10, greaterThanOrEqualTo(420));
      expect(m.fired.keys, containsAll(['wave1', 'wave2', 'wave3', 'wave4']));
    });

    test('M2 : défaite si le centre-ville tombe', () {
      final w = start('m2');
      damageBuilding(w, tc(w), 999999, srcOwner: 1);
      runUntil(w, () => w.mission!.status != MissionStatus.running, limit: 100);
      expect(w.mission!.status, MissionStatus.lost);
      expect(w.winnerTeam, missionLostTeam);
    });

    test('M3 : les hameaux protégés, les raids repoussés', () {
      final w = start('m3');
      final m = w.mission!;
      final huts = m.tags['village']!;
      final b = w.buildings[huts.first]!;
      guard(w, b.tx + 3, b.ty + 3, n: 24);
      final b2 = w.buildings[huts.last]!;
      guard(w, b2.tx + 3, b2.ty + 3, n: 24);
      runUntil(w, () => m.status != MissionStatus.running, limit: 4000);
      expect(m.won, isTrue, reason: 'statut ${m.status}, flags ${m.flags}');
      expect(m.flags, contains('raids_over'));
    });

    test('M3 : perdre deux huttes perd la mission', () {
      final w = start('m3');
      final huts = w.mission!.tags['village']!;
      for (final id in huts.take(2)) {
        damageBuilding(w, w.buildings[id]!, 99999, srcOwner: 1);
      }
      runUntil(w, () => w.mission!.status != MissionStatus.running, limit: 100);
      expect(w.mission!.status, MissionStatus.lost);
      expect(w.mission!.loseReason, 'protect');
    });

    test('M4 : camp minier, embuscade, extraction', () {
      final w = start('m4');
      final m = w.mission!;
      final c = tc(w);
      final camp = spot(w, 'mining_camp', c.tx + 4, c.ty);
      w.submit(
        BuildCmd(
          0,
          [mine(w, id: 'villager').first.id],
          'mining_camp',
          camp.x,
          camp.y,
        ),
      );
      runUntil(w, () => m.objectiveState('camp') == ObjState.done);
      expect(m.objectiveState('ambush'), ObjState.hidden);
      w.players[0].stats.gathered[3] = 130; // fer
      run(w, 10);
      expect(m.fired, contains('ambush'));
      expect(m.objectiveState('ambush'), ObjState.active);
      expect(tagged(w, 'ambush'), hasLength(greaterThanOrEqualTo(8)));
      guard(w, c.tx + 3, c.ty + 3, n: 20);
      runUntil(
        w,
        () => m.objectiveState('ambush') == ObjState.done,
        limit: 4000,
      );
      w.players[0].stats
        ..gathered[3] = 300
        ..gathered[4] = 200;
      runUntil(w, () => m.status != MissionStatus.running, limit: 100);
      expect(m.won, isTrue);
    });

    test('M5 : la caravane arrive ; sa mort perd la mission', () {
      final w = start('m5');
      final m = w.mission!;
      final caravan = tagged(w, 'caravan').single;
      final p1 = w.players[1];
      teleport(w, caravan, w.map.width ~/ 2, w.map.height ~/ 2);
      run(w, 10);
      expect(m.fired, contains('ambush1'));
      expect(tagged(w, 'bandits'), isNotEmpty);
      teleport(w, caravan, p1.startX + 4, p1.startY + 4);
      run(w, 10);
      expect(m.fired, contains('ambush2'));
      expect(m.won, isTrue);

      final w2 = start('m5');
      damageUnit(w2, tagged(w2, 'caravan').single, 9999, srcOwner: 1);
      runUntil(
        w2,
        () => w2.mission!.status != MissionStatus.running,
        limit: 100,
      );
      expect(w2.mission!.status, MissionStatus.lost);
    });

    test('M6 : armée détruite puis centre-ville ennemi', () {
      final w = start('m6');
      final m = w.mission!;
      for (final u in tagged(w, 'enemy_army')) {
        damageUnit(w, u, 9999, srcOwner: 0);
      }
      run(w, 20);
      expect(m.objectiveState('army'), ObjState.done);
      expect(m.running, isTrue);
      damageBuilding(w, tc(w, 1), 999999, srcOwner: 0);
      runUntil(w, () => m.status != MissionStatus.running, limit: 100);
      expect(m.won, isTrue);
    });

    test('M7 : boss à 5 min, deux fins selon les tours', () {
      for (final destroyTowers in [true, false]) {
        final w = start('m7');
        final m = w.mission!;
        expect(m.objectiveState('boss'), ObjState.hidden);
        runUntil(w, () => m.fired.containsKey('boss'), limit: 3100);
        expect(m.objectiveState('boss'), ObjState.active);
        final boss = tagged(w, 'boss').single;
        expect(boss.def.id, 'hero_kaba');
        damageBuilding(
          w,
          w.buildings[m.tags['fortress']!.first]!,
          999999,
          srcOwner: 0,
        );
        run(w, 20);
        expect(m.running, isTrue, reason: 'le boss vit encore');
        if (destroyTowers) {
          for (final id in m.tags['towers']!) {
            if (w.buildings[id] != null) {
              damageBuilding(w, w.buildings[id]!, 999999, srcOwner: 0);
            }
          }
        }
        damageUnit(w, boss, 99999, srcOwner: 0);
        runUntil(w, () => m.status != MissionStatus.running, limit: 200);
        expect(m.won, isTrue);
        expect(m.ending, destroyTowers ? 'glorious' : 'bitter');
        expect(m.endingText, isNotEmpty);
      }
    });
  });

  group('sauvegarde et déterminisme', () {
    test('sauvegarde en cours de mission : reprise identique', () {
      final a = start('m2');
      run(a, 1000);
      expect(a.mission!.fired, contains('wave1'));
      final bytes = SaveCodec.encode(a);
      final b = SaveCodec.decode(testDefs, bytes)
        ..checkInvariantsEachTick = true;
      expect(b.missionRaw, isNotNull);
      attachMission(b, campaign);
      expect(b.mission, isNotNull);
      expect(b.stateHash(), a.stateHash());
      run(a, 600);
      run(b, 600);
      expect(b.stateHash(), a.stateHash());
      expect(b.mission!.fired.keys.toSet(), a.mission!.fired.keys.toSet());
    });

    test('deux exécutions identiques donnent le même hash', () {
      final a = start('m3');
      final b = start('m3');
      run(a, 1500);
      run(b, 1500);
      expect(a.stateHash(), b.stateHash());
    });

    test('une mission gagnée reste gagnée après rechargement', () {
      final w = start('m6');
      for (final u in tagged(w, 'enemy_army')) {
        damageUnit(w, u, 9999, srcOwner: 0);
      }
      damageBuilding(w, tc(w, 1), 999999, srcOwner: 0);
      runUntil(w, () => w.mission!.status != MissionStatus.running, limit: 200);
      final b = SaveCodec.decode(testDefs, SaveCodec.encode(w));
      attachMission(b, campaign);
      expect(b.mission!.won, isTrue);
      expect(b.mission!.stars, w.mission!.stars);
      expect(b.gameOver, isTrue);
    });
  });
}
