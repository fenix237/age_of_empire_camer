import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/rng.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';
import '../helpers/test_defs.dart';

/// Ressources « engagées » : stock + coûts payés en file + coût des
/// bâtiments posés (progression nulle) = quantité conservée par les commandes
/// de production, de pose et d'annulation (aucun tick ne passe).
Stock _committed(World w, int owner) {
  final s = w.players[owner].stock.copy();
  for (final b in w.buildings.values) {
    if (b.owner != owner) continue;
    for (final q in b.queue) {
      s.add(q.paid);
    }
  }
  return s;
}

void main() {
  test('conservation : séquences aléatoires de mise en file / annulation', () {
    for (var seed = 1; seed <= 150; seed++) {
      final r = Rng(seed);
      final w = blankWorld(
        stock: Stock.of(<int>[3000, 3000, 3000, 3000, 3000]),
      );
      final tc = addBuilding(w, 'town_center', 5, 5);
      final barracks = addBuilding(w, 'barracks', 12, 5);
      final forge = addBuilding(w, 'forge', 18, 5);
      final initial = w.players[0].stock.copy();
      final all = <int>[tc.id, barracks.id, forge.id];
      for (var i = 0; i < 120; i++) {
        final b = all[r.nextInt(all.length)];
        final k = r.nextInt(10);
        if (k < 4) {
          final building = w.buildings[b]!;
          if (building.def.trains.isNotEmpty) {
            TrainCmd(
              0,
              b,
              building.def.trains[r.nextInt(building.def.trains.length)],
            ).apply(w);
          }
        } else if (k < 6) {
          final building = w.buildings[b]!;
          if (building.def.researches.isNotEmpty) {
            ResearchCmd(
              0,
              b,
              building.def.researches[r.nextInt(
                building.def.researches.length,
              )],
            ).apply(w);
          }
        } else {
          CancelQueueCmd(0, b, r.range(-1, 5)).apply(w);
        }
        expect(_committed(w, 0), initial, reason: 'graine $seed pas $i');
        expect(w.players[0].stock.v.every((e) => e >= 0), isTrue);
      }
      // Tout annuler : on retrouve exactement la mise de départ.
      for (final b in all) {
        while (w.buildings[b]!.queue.isNotEmpty) {
          expect(CancelQueueCmd(0, b, 0).apply(w), CmdResult.ok);
        }
      }
      expect(w.players[0].stock, initial, reason: 'graine $seed');
    }
  });

  test(
    'conservation : poser puis annuler à progression nulle rembourse tout',
    () {
      for (final id in [
        'hut',
        'granary',
        'barracks',
        'forge',
        'market',
        'field',
      ]) {
        final w = blankWorld();
        w.players[0].age = 1;
        final u = addUnit(w, 'villager', 10, 10);
        final initial = w.players[0].stock.copy();
        expect(
          BuildCmd(0, [u.id], id, 14, 10).apply(w),
          CmdResult.ok,
          reason: id,
        );
        final b = w.buildings.values.single;
        expect(b.progressMilli, 0);
        expect(DeleteCmd(0, b.id).apply(w), CmdResult.ok);
        expect(w.players[0].stock, initial, reason: id);
      }
    },
  );

  test(
    'annulation à n’importe quel avancement : remboursement exact et monotone',
    () {
      for (final cut in [0, 7, 30, 99, 250, 500]) {
        final w = blankWorld();
        final u = addUnit(w, 'villager', 12, 10);
        final initial = w.players[0].stock.copy();
        final def = testDefs.building('barracks');
        w.submit(BuildCmd(0, [u.id], 'barracks', 14, 10));
        run(w, cut + 1);
        final b = w.buildings.values.single;
        final progress = b.progressMilli;
        w.submit(DeleteCmd(0, b.id));
        w.step();
        final refund = def.cost.scaled(
          b.totalBuildMilli - progress,
          b.totalBuildMilli,
        );
        final spent = initial.copy()..subtract(w.players[0].stock);
        final expectedSpent = def.cost.copy()..subtract(refund);
        expect(spent, expectedSpent, reason: 'coupe à $cut ticks');
        for (final r in Res.values) {
          expect(spent[r] >= 0 && spent[r] <= def.cost[r], isTrue);
        }
      }
    },
  );

  test(
    'aucune ressource négative après toute séquence de commandes valides ou non',
    () {
      final w = blankWorld(stock: Stock.of(<int>[120, 90, 40, 0, 0]));
      final tc = addBuilding(w, 'town_center', 5, 5);
      final forge = addBuilding(w, 'forge', 12, 5);
      final r = Rng(9);
      for (var i = 0; i < 400; i++) {
        TrainCmd(0, tc.id, 'villager', count: r.range(1, 4)).apply(w);
        ResearchCmd(
          0,
          forge.id,
          testDefs.techs[r.nextInt(testDefs.techs.length)].id,
        ).apply(w);
        if (r.chance(40)) CancelQueueCmd(0, tc.id, r.range(0, 3)).apply(w);
        if (r.chance(10)) w.step();
        expect(
          w.players[0].stock.v.every((e) => e >= 0),
          isTrue,
          reason: 'pas $i',
        );
      }
    },
  );
}
