import 'dart:io';

import 'package:age_of_empire_camer/sim/commands/contextual.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/save/save_codec.dart';
import 'package:age_of_empire_camer/sim/testing/economy_bot.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

final bool _full = Platform.environment['SIM_FULL'] == '1';

World _play(int seed, int ticks, {bool invariants = false, World? from}) {
  final w = from ?? createGame(testDefs, seed: seed);
  w.checkInvariantsEachTick = invariants;
  final bots = [EconomyBot(0), EconomyBot(1)];
  for (var t = 0; t < ticks; t++) {
    for (final b in bots) {
      b.update(w);
    }
    w.step();
  }
  return w;
}

void main() {
  test('partie « économie seule » de 30 minutes sans violation', () {
    final w = _play(11, 18000, invariants: true);
    expect(w.violations, isEmpty, reason: w.violations.take(5).join('\n'));
    for (final p in w.players) {
      final villagers = w.unitsOf(p.id).where((u) => u.def.villager).length;
      expect(villagers, greaterThan(12), reason: 'joueur ${p.id}');
      final built = w.buildings.values
          .where((b) => b.owner == p.id && b.complete)
          .map((b) => b.def.id)
          .toSet();
      expect(built, containsAll(['town_center', 'hut']));
      expect(p.popCap, greaterThan(10));
      expect(p.stock.v.every((e) => e >= 0), isTrue);
    }
  });

  test('sauvegarde → chargement au milieu de la partie : hash identique', () {
    final a = _play(12, 9000);
    final b = SaveCodec.decode(testDefs, SaveCodec.encode(a));
    expect(b.stateHash(), a.stateHash());
    // Les deux continuent avec les mêmes décisions de bots.
    _play(12, 4000, from: a);
    _play(12, 4000, from: b);
    expect(b.stateHash(), a.stateHash());
  });

  test('la partie est déterministe d’une exécution à l’autre', () {
    expect(_play(13, 6000).stateHash(), _play(13, 6000).stateHash());
  });

  test('l’économie produit réellement des ressources (bois, nourriture)', () {
    final w = _play(14, 12000);
    final p = w.players[0];
    final total = p.stock.v.fold<int>(0, (a, b) => a + b);
    expect(total, greaterThan(300));
    expect(w.nodes.length, lessThan(2000));
  });

  test(
    'porte de sortie : parties headless aléatoires sans violation',
    () {
      final n = _full ? 150 : 6;
      for (var s = 1; s <= n; s++) {
        final w = createGame(
          testDefs,
          seed: s * 17,
          size: 48 + (s % 3) * 16,
          players: 2 + s % 3,
        )..checkInvariantsEachTick = true;
        final bots = [for (var i = 0; i < w.players.length; i++) EconomyBot(i)];
        for (var t = 0; t < 4000; t++) {
          for (final b in bots) {
            b.update(w);
          }
          w.step();
        }
        expect(w.violations, isEmpty, reason: 'graine $s');
      }
    },
    timeout: const Timeout(Duration(hours: 1)),
  );

  group('ordres contextuels', () {
    test('sol → déplacer ; ressource → récolter ; mixte → les deux', () {
      final w = createGame(testDefs, seed: 3, size: 48);
      final v = w.unitsOf(0).first;
      final tree = w.nodes.values.firstWhere((n) => n.res == Res.wood);
      final cmds = contextualCommands(
        w,
        0,
        [v.id],
        tx: tree.tx,
        ty: tree.ty,
        targetId: tree.id,
      );
      expect(cmds.single.type, 'gather');
      expect(
        contextualCommands(w, 0, [v.id], tx: 3, ty: 3).single.type,
        'move',
      );
      final soldier = w.spawnUnit(testDefs.unit('spearman'), 0, v.x, v.y);
      final mixed = contextualCommands(
        w,
        0,
        [v.id, soldier.id],
        tx: tree.tx,
        ty: tree.ty,
        targetId: tree.id,
      );
      expect(mixed.map((c) => c.type), ['gather', 'move']);
      expect(contextualCommands(w, 0, [], tx: 1, ty: 1), isEmpty);
      expect(contextualCommands(w, 0, [9999], tx: 1, ty: 1), isEmpty);
    });

    test(
      'ennemi → attaquer ; bâtiment allié → garnison / réparer / construire',
      () {
        final w = createGame(testDefs, seed: 3, size: 48);
        final v = w.unitsOf(0).first;
        final soldier = w.spawnUnit(testDefs.unit('spearman'), 0, v.x, v.y);
        final enemy = w.unitsOf(1).first;
        final atk = contextualCommands(
          w,
          0,
          [soldier.id, v.id],
          tx: 0,
          ty: 0,
          targetId: enemy.id,
        );
        expect(atk.first.type, 'attack');
        final tc = w.buildings.values.firstWhere((b) => b.owner == 0);
        expect(
          contextualCommands(
            w,
            0,
            [soldier.id],
            tx: tc.tx,
            ty: tc.ty,
            targetId: tc.id,
          ).single.type,
          'garrison',
        );
        tc.hp = 10;
        expect(
          contextualCommands(
            w,
            0,
            [v.id],
            tx: tc.tx,
            ty: tc.ty,
            targetId: tc.id,
          ).single.type,
          'repair',
        );
        final hut = w.spawnBuilding(testDefs.building('hut'), 0, 40, 40);
        expect(
          contextualCommands(
            w,
            0,
            [v.id],
            tx: 40,
            ty: 40,
            targetId: hut.id,
          ).single.type,
          'repair',
        );
        final field = w.spawnBuilding(
          testDefs.building('field'),
          0,
          30,
          40,
          complete: true,
        );
        expect(
          contextualCommands(
            w,
            0,
            [v.id],
            tx: 30,
            ty: 40,
            targetId: field.id,
          ).single.type,
          'gather',
        );
      },
    );

    test('rallyCommand et sélection tolérante', () {
      final w = createGame(testDefs, seed: 3, size: 48);
      final tc = w.buildings.values.firstWhere((b) => b.owner == 0);
      final tree = w.nodes.values.first;
      final c = rallyCommand(
        w,
        0,
        tc.id,
        tx: tree.tx,
        ty: tree.ty,
        targetId: tree.id,
      );
      expect(c.type, 'rally');
      final v = w.unitsOf(0).first;
      expect(unitNear(w, v.x + 20, v.y + 10, 64)?.id, isNotNull);
      expect(unitNear(w, -100000, -100000, 64), isNull);
      expect(unitNear(w, v.x, v.y, 64, excludeOwner: 0)?.owner, isNot(0));
      expect(entityAtTile(w, tree.tx, tree.ty), tree.id);
      expect(entityAtTile(w, -1, -1), -1);
      expect(w.units.values.every((u) => u.state != UnitState.dead), isTrue);
    });
  });
}
