import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';
import '../helpers/test_defs.dart';

void main() {
  group('récolte', () {
    test('un villageois récolte du bois et le dépose au centre-ville', () {
      final w = blankWorld();
      addBuilding(w, 'town_center', 5, 5);
      addNode(w, 'tree', 14, 7);
      final tree = addNode(w, 'tree', 14, 8);
      final u = addUnit(w, 'villager', 9, 8);
      w.players[0].stock = Stock();
      w.submit(GatherCmd(0, [u.id], tree.id));
      runUntil(w, () => w.players[0].stock[Res.wood] > 0, limit: 1500);
      expect(w.players[0].stock[Res.wood], 10);
      expect(u.state, UnitState.gathering);
      expectHealthy(w);
    });

    test('le villageois repart seul vers la ressource après un dépôt', () {
      final w = blankWorld();
      addBuilding(w, 'town_center', 5, 5);
      final tree = addNode(w, 'berries', 14, 8);
      final u = addUnit(w, 'villager', 9, 8);
      w.players[0].stock = Stock();
      w.submit(GatherCmd(0, [u.id], tree.id));
      runUntil(w, () => w.players[0].stock[Res.food] >= 30, limit: 4000);
      expect(w.players[0].stock[Res.food] % 10, 0);
      expectHealthy(w);
    });

    test('la capacité de portage et la vitesse suivent les recherches', () {
      final w = blankWorld();
      final p = w.players[0];
      final u = testDefs.unit('villager');
      final base = p.carryCapacity(u);
      final rate = p.gatherPerTick(u, Res.wood);
      p
        ..addTech(testDefs.tech('carry_1'))
        ..addTech(testDefs.tech('gather_wood_1'))
        ..addTech(testDefs.tech('gather_wood_1')); // idempotent
      expect(p.carryCapacity(u), base + 5);
      expect(p.gatherPerTick(u, Res.wood), greaterThan(rate));
      expect(p.gatherPerTick(u, Res.food), p.gatherPerTick(u, Res.food));
      expect(p.techs, hasLength(2));
    });

    test(
      'ressource épuisée : retirée, case libérée, passage à la suivante',
      () {
        final w = blankWorld();
        addBuilding(w, 'town_center', 5, 5);
        final a = addNode(w, 'tree', 14, 8)..amount = 3;
        final b = addNode(w, 'tree', 14, 9);
        final u = addUnit(w, 'villager', 12, 8);
        w.players[0].stock = Stock();
        w.submit(GatherCmd(0, [u.id], a.id));
        runUntil(w, () => !w.nodes.containsKey(a.id), limit: 800);
        expect(w.map.occupant[w.map.index(14, 8)], 0);
        // Puis la même ressource voisine est visée automatiquement.
        runUntil(w, () => u.targetId == b.id, limit: 800);
        expect(u.state, UnitState.gathering);
        expectHealthy(w);
      },
    );

    test('plus aucune ressource proche : le villageois devient inactif', () {
      final w = blankWorld();
      addBuilding(w, 'town_center', 5, 5);
      final a = addNode(w, 'tree', 14, 8)..amount = 2;
      addNode(w, 'tree', 38, 38); // trop loin (> 10 cases)
      final u = addUnit(w, 'villager', 12, 8);
      w.submit(GatherCmd(0, [u.id], a.id));
      runUntil(w, () => u.isIdle && w.tick > 5, limit: 1500);
      expect(u.carryAmt, 0, reason: 'la charge a été déposée avant');
      expectHealthy(w);
    });

    test('sans dépôt : le villageois plein reste inactif avec sa charge', () {
      final w = blankWorld();
      final tree = addNode(w, 'tree', 14, 8);
      final u = addUnit(w, 'villager', 12, 8);
      w.submit(GatherCmd(0, [u.id], tree.id));
      runUntil(w, () => u.isIdle && w.tick > 5, limit: 1500);
      expect(u.carryAmt, 10);
      expect(u.carryType, Res.wood);
      expectHealthy(w);
    });

    test('dépôt détruit en route : un autre dépôt est choisi', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      final camp = addBuilding(w, 'lumber_camp', 20, 8);
      final tree = addNode(w, 'tree', 17, 8);
      final u = addUnit(w, 'villager', 16, 8);
      w.players[0].stock = Stock();
      w.submit(GatherCmd(0, [u.id], tree.id));
      runUntil(w, () => u.phase == Phase.returning, limit: 1500);
      w.removeBuilding(camp, destroyed: true);
      runUntil(w, () => w.players[0].stock[Res.wood] > 0, limit: 2500);
      expect(w.buildings.containsKey(tc.id), isTrue);
      expectHealthy(w);
    });

    test('changer de type de ressource jette la charge précédente', () {
      final w = blankWorld();
      addBuilding(w, 'town_center', 5, 5);
      final tree = addNode(w, 'tree', 14, 8);
      final berries = addNode(w, 'berries', 14, 12);
      final u = addUnit(w, 'villager', 12, 8)
        ..carryRes = Res.wood.index
        ..carryAmt = 4;
      w.submit(GatherCmd(0, [u.id], berries.id));
      w.step();
      expect(u.carryAmt, 0);
      expect(tree.amount, 100);
      expectHealthy(w);
    });

    test('un soldat ne récolte pas, cible invalide refusée', () {
      final w = blankWorld();
      final tree = addNode(w, 'tree', 14, 8);
      final s = addUnit(w, 'spearman', 12, 8);
      final v = addUnit(w, 'villager', 12, 9);
      expect(GatherCmd(0, [s.id], tree.id).apply(w), CmdResult.noUnits);
      expect(GatherCmd(0, [v.id], 9999).apply(w), CmdResult.wrongTarget);
    });
  });

  group('champs', () {
    test('les champs se travaillent, s’épuisent et se replantent', () {
      final w = blankWorld();
      addBuilding(w, 'town_center', 5, 5);
      final f = addBuilding(w, 'field', 12, 8);
      final u = addUnit(w, 'villager', 11, 8);
      w.players[0].stock = Stock.of([0, 500, 0, 0, 0]);
      f.stock = 12;
      w.submit(GatherCmd(0, [u.id], f.id));
      runUntil(w, () => f.stock == 0);
      runUntil(w, () => f.stock > 0, why: 'replantation auto');
      expect(w.players[0].stock[Res.wood], lessThan(500));
      expectHealthy(w);
    });

    test('reseed manuel : coûte du bois, seulement si le champ est vide', () {
      final w = blankWorld();
      final f = addBuilding(w, 'field', 12, 8);
      expect(ReseedCmd(0, f.id).apply(w), CmdResult.cannotAfford);
      f.stock = 0;
      final before = w.players[0].stock[Res.wood];
      expect(ReseedCmd(0, f.id).apply(w), CmdResult.ok);
      expect(f.stock, 175);
      expect(w.players[0].stock[Res.wood], before - 60);
      expect(ReseedCmd(1, f.id).apply(w), CmdResult.wrongTarget);
    });

    test('un champ n’accepte qu’un villageois à la fois', () {
      final w = blankWorld();
      addBuilding(w, 'town_center', 5, 5);
      final f = addBuilding(w, 'field', 12, 8);
      final a = addUnit(w, 'villager', 11, 8);
      final b = addUnit(w, 'villager', 11, 9);
      w.submit(GatherCmd(0, [a.id, b.id], f.id));
      run(w, 300);
      expect(
        [a, b]
            .where((u) => u.targetId == f.id && u.state == UnitState.gathering)
            .length,
        greaterThanOrEqualTo(1),
      );
      expectHealthy(w);
    });
  });

  group('construction', () {
    test('hutte : coût payé, construite, population +5', () {
      final w = blankWorld();
      final u = addUnit(w, 'villager', 10, 10);
      final before = w.players[0].stock.copy();
      w.submit(BuildCmd(0, [u.id], 'hut', 12, 10));
      w.step();
      expect(w.players[0].stock[Res.wood], before[Res.wood] - 25);
      final b = w.buildings.values.single;
      expect(b.complete, isFalse);
      expect(b.hp, lessThan(b.maxHp));
      runUntil(w, () => b.complete, limit: 600);
      expect(b.hp, b.maxHp);
      w.step();
      expect(w.players[0].popCap, 5);
      expectHealthy(w);
    });

    test(
      'plusieurs bâtisseurs construisent plus vite (rendement décroissant)',
      () {
        int timeWith(int n) {
          final w = blankWorld();
          final ids = [
            for (var i = 0; i < n; i++) addUnit(w, 'villager', 10, 10 + i).id,
          ];
          w.submit(BuildCmd(0, ids, 'barracks', 14, 10));
          w.step();
          final b = w.buildings.values.single;
          return runUntil(w, () => b.complete);
        }

        final t1 = timeWith(1);
        final t2 = timeWith(2);
        final t4 = timeWith(4);
        expect(t2, lessThan(t1));
        expect(t4, lessThan(t2));
        expect(t2 * 2, greaterThan(t1), reason: 'rendement décroissant');
      },
    );

    test('placement refusé : ressource, hors carte, eau, ennemi, fonds', () {
      final w = blankWorld();
      final u = addUnit(w, 'villager', 10, 10);
      addNode(w, 'tree', 20, 20);
      addUnit(w, 'spearman', 25, 25, owner: 1);
      for (var x = 0; x < 6; x++) {
        w.map.terrain[w.map.index(30 + x, 5)] = 4; // eau peu profonde
      }
      expect(
        BuildCmd(0, [u.id], 'hut', 20, 20).apply(w),
        CmdResult.badPlacement,
      );
      expect(
        BuildCmd(0, [u.id], 'hut', 39, 39).apply(w),
        CmdResult.badPlacement,
      );
      expect(
        BuildCmd(0, [u.id], 'hut', -1, 3).apply(w),
        CmdResult.badPlacement,
      );
      expect(
        BuildCmd(0, [u.id], 'hut', 30, 5).apply(w),
        CmdResult.badPlacement,
      );
      expect(
        BuildCmd(0, [u.id], 'hut', 25, 25).apply(w),
        CmdResult.badPlacement,
      );
      expect(BuildCmd(0, [u.id], 'zzz', 5, 5).apply(w), CmdResult.notFound);
      w.players[0].stock = Stock();
      expect(BuildCmd(0, [u.id], 'hut', 5, 5).apply(w), CmdResult.cannotAfford);
      expect(w.buildings, isEmpty);
      expect(w.players[0].stock.isZero, isTrue);
    });

    test('placement simultané sur la même zone : le second est refusé', () {
      final w = blankWorld();
      final a = addUnit(w, 'villager', 10, 10);
      final b = addUnit(w, 'villager', 11, 10);
      expect(BuildCmd(0, [a.id], 'hut', 14, 10).apply(w), CmdResult.ok);
      final stock = w.players[0].stock.copy();
      expect(
        BuildCmd(0, [b.id], 'granary', 14, 10).apply(w),
        CmdResult.badPlacement,
      );
      expect(
        BuildCmd(0, [b.id], 'hut', 15, 11).apply(w),
        CmdResult.badPlacement,
      );
      expect(w.players[0].stock, stock, reason: 'aucun coût prélevé');
      expect(w.buildings.length, 1);
    });

    test('construction hors zone explorée interdite', () {
      final w = blankWorld();
      final u = addUnit(w, 'villager', 10, 10);
      w.players[0].explored.fillRange(0, w.players[0].explored.length, 0);
      expect(BuildCmd(0, [u.id], 'hut', 5, 5).apply(w), CmdResult.unexplored);
    });

    test('les unités sur l’emprise sont repoussées automatiquement', () {
      final w = blankWorld();
      final builder = addUnit(w, 'villager', 8, 8);
      final blocker = addUnit(w, 'villager', 12, 10);
      expect(
        BuildCmd(0, [builder.id], 'hut', 12, 10).apply(w),
        CmdResult.ok,
      );
      expect(
        w.buildings.values.single.coversTile(blocker.tileX, blocker.tileY),
        isFalse,
      );
      run(w, 3);
      expectHealthy(w);
    });

    test('annulation en construction : remboursement exact du restant', () {
      final w = blankWorld();
      final u = addUnit(w, 'villager', 10, 10);
      final before = w.players[0].stock.copy();
      w.submit(BuildCmd(0, [u.id], 'barracks', 14, 10));
      run(w, 120);
      final b = w.buildings.values.single;
      final progress = b.progressMilli;
      expect(progress, greaterThan(0));
      w.submit(DeleteCmd(0, b.id));
      w.step();
      final left = b.totalBuildMilli - progress;
      final refund = b.def.cost.scaled(left, b.totalBuildMilli);
      final spent = b.def.cost.copy()..subtract(refund);
      final expected = before.copy()..subtract(spent);
      expect(w.players[0].stock, expected);
      expect(w.buildings, isEmpty);
      run(w, 5);
      expect(u.isIdle, isTrue);
      expectHealthy(w);
    });

    test(
      'supprimer un bâtiment terminé : pas de remboursement, case libérée',
      () {
        final w = blankWorld();
        final b = addBuilding(w, 'hut', 12, 10);
        final before = w.players[0].stock.copy();
        expect(DeleteCmd(1, b.id).apply(w), CmdResult.notOwned);
        expect(DeleteCmd(0, b.id).apply(w), CmdResult.ok);
        expect(w.players[0].stock, before);
        expect(w.map.occupant[w.map.index(12, 10)], 0);
        expect(DeleteCmd(0, b.id).apply(w), CmdResult.notFound);
      },
    );

    test(
      'bâtiment en construction détruit par l’ennemi : aucun remboursement',
      () {
        final w = blankWorld();
        final u = addUnit(w, 'villager', 10, 10);
        w.submit(BuildCmd(0, [u.id], 'hut', 12, 10));
        run(w, 5);
        final b = w.buildings.values.single;
        final stock = w.players[0].stock.copy();
        w.removeBuilding(b, destroyed: true);
        run(w, 3);
        expect(w.players[0].stock, stock);
        expect(u.isIdle, isTrue);
        expectHealthy(w);
      },
    );

    test('après un camp, le bâtisseur récolte à proximité', () {
      final w = blankWorld();
      addBuilding(w, 'town_center', 5, 5);
      final u = addUnit(w, 'villager', 10, 10);
      final tree = addNode(w, 'tree', 16, 11);
      w.submit(BuildCmd(0, [u.id], 'lumber_camp', 14, 10));
      runUntil(w, () => u.state == UnitState.gathering, limit: 1500);
      expect(u.targetId, tree.id);
    });

    test('bâtisseur d’un champ : il le cultive aussitôt', () {
      final w = blankWorld();
      addBuilding(w, 'town_center', 5, 5);
      final u = addUnit(w, 'villager', 10, 10);
      w.submit(BuildCmd(0, [u.id], 'field', 12, 10));
      runUntil(w, () => u.state == UnitState.gathering, limit: 1500);
      expect(w.nodes, isEmpty);
    });

    test('réparation : coûte des ressources, s’arrête sans fonds', () {
      final w = blankWorld();
      final b = addBuilding(w, 'barracks', 12, 10)..hp = 100;
      final u = addUnit(w, 'villager', 10, 10);
      final before = w.players[0].stock.copy();
      w.submit(RepairCmd(0, [u.id], b.id));
      runUntil(w, () => b.hp == b.maxHp, limit: 4000);
      final spent = before.copy()..subtract(w.players[0].stock);
      expect(spent[Res.wood], greaterThan(0));
      expect(spent[Res.wood], lessThanOrEqualTo(175 ~/ 2 + 1));
      expect(RepairCmd(0, [u.id], b.id).apply(w), CmdResult.nothingToDo);
      b.hp = 100;
      w.players[0].stock = Stock();
      w.submit(RepairCmd(0, [u.id], b.id));
      run(w, 300);
      expect(b.hp, lessThan(b.maxHp));
      expect(u.isIdle, isTrue);
      expect(w.players[0].stock.v.every((e) => e >= 0), isTrue);
      expectHealthy(w);
    });
  });

  group('production', () {
    test('entraîner un villageois : coût payé, apparition, ralliement', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      w.players[0].stock = Stock.of([200, 0, 0, 0, 0]);
      w.submit(SetRallyCmd(0, tc.id, 20, 20));
      w.submit(TrainCmd(0, tc.id, 'villager'));
      w.step();
      expect(w.players[0].stock[Res.food], 150);
      expect(tc.queue, hasLength(1));
      w.step(); // la population est recalculée au début du tick
      runUntil(w, () => w.units.isNotEmpty, limit: 400);
      final u = w.units.values.single;
      expect(u.owner, 0);
      runUntil(w, () => u.isIdle && u.tileX == 20, limit: 600);
      expect(tc.queue, isEmpty);
      expectHealthy(w);
    });

    test('ralliement sur une ressource : le villageois récolte', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      final tree = addNode(w, 'tree', 20, 20);
      w.submit(SetRallyCmd(0, tc.id, 20, 20, tree.id));
      w.submit(TrainCmd(0, tc.id, 'villager'));
      runUntil(w, () => w.units.isNotEmpty, limit: 400);
      run(w, 2);
      final u = w.units.values.single;
      expect(u.state, UnitState.gathering);
      expect(u.targetId, tree.id);
    });

    test('annulation : remboursement exact, à tout moment de la file', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      final before = w.players[0].stock.copy();
      w.submit(TrainCmd(0, tc.id, 'villager', count: 3));
      run(w, 20);
      expect(tc.queue, hasLength(3));
      w.submit(CancelQueueCmd(0, tc.id, 0));
      w.submit(CancelQueueCmd(0, tc.id, 1));
      w.step();
      expect(tc.queue, hasLength(1));
      w.submit(CancelQueueCmd(0, tc.id, 0));
      w.step();
      expect(tc.queue, isEmpty);
      expect(w.players[0].stock, before);
      expect(CancelQueueCmd(0, tc.id, 0).apply(w), CmdResult.invalid);
      expectHealthy(w);
    });

    test('plafond de population : la production attend de la place', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5); // cap 10
      for (var i = 0; i < 10; i++) {
        addUnit(w, 'villager', 20 + i % 5, 20 + i ~/ 5);
      }
      w.submit(TrainCmd(0, tc.id, 'villager'));
      run(w, 400);
      expect(w.units.length, 10);
      expect(tc.queue, hasLength(1));
      expect(tc.queue.first.remaining, 0);
      // Une hutte libère de la place.
      addBuilding(w, 'hut', 30, 30);
      run(w, 5);
      expect(w.units.length, 11);
      expect(tc.queue, isEmpty);
      expectHealthy(w);
    });

    test('file pleine, fonds insuffisants, bâtiment incomplet, âge', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      final barracks = addBuilding(w, 'barracks', 15, 5);
      final building = addBuilding(w, 'barracks', 25, 5, complete: false);
      for (var i = 0; i < 5; i++) {
        expect(TrainCmd(0, tc.id, 'villager').apply(w), CmdResult.ok);
      }
      expect(TrainCmd(0, tc.id, 'villager').apply(w), CmdResult.queueFull);
      expect(TrainCmd(0, barracks.id, 'archer').apply(w), CmdResult.locked);
      expect(
        TrainCmd(0, barracks.id, 'villager').apply(w),
        CmdResult.wrongTarget,
      );
      expect(
        TrainCmd(0, building.id, 'spearman').apply(w),
        CmdResult.notComplete,
      );
      expect(TrainCmd(1, barracks.id, 'spearman').apply(w), CmdResult.notOwned);
      expect(const TrainCmd(0, 9999, 'spearman').apply(w), CmdResult.notFound);
      expect(
        TrainCmd(0, barracks.id, 'spearman', count: 0).apply(w),
        CmdResult.invalid,
      );
      w.players[0].stock = Stock();
      expect(
        TrainCmd(0, barracks.id, 'spearman').apply(w),
        CmdResult.cannotAfford,
      );
    });

    test('recherche : appliquée à la fin, une seule fois, remboursable', () {
      final w = blankWorld();
      final forge = addBuilding(w, 'forge', 15, 5);
      final p = w.players[0];
      final before = p.stock.copy();
      expect(ResearchCmd(0, forge.id, 'carry_1').apply(w), CmdResult.ok);
      expect(
        ResearchCmd(0, forge.id, 'carry_1').apply(w),
        CmdResult.nothingToDo,
      );
      expect(ResearchCmd(0, forge.id, 'nope').apply(w), CmdResult.wrongTarget);
      run(w, 10);
      expect(CancelQueueCmd(0, forge.id, 0).apply(w), CmdResult.ok);
      expect(p.stock, before);
      expect(ResearchCmd(0, forge.id, 'carry_1').apply(w), CmdResult.ok);
      final base = p.carryCapacity(testDefs.unit('villager'));
      runUntil(w, () => p.hasTech(testDefs.tech('carry_1').index), limit: 400);
      expect(p.carryCapacity(testDefs.unit('villager')), base + 5);
      expect(
        ResearchCmd(0, forge.id, 'carry_1').apply(w),
        CmdResult.nothingToDo,
      );
      expectHealthy(w);
    });

    test('suppression d’un bâtiment : la file est remboursée', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      final before = w.players[0].stock.copy();
      w.submit(TrainCmd(0, tc.id, 'villager', count: 2));
      run(w, 3);
      w.submit(DeleteCmd(0, tc.id));
      w.step();
      expect(w.players[0].stock, before);
    });
  });

  group('marché', () {
    test('échange avec frais ; refusé sans marché ni fonds', () {
      final w = blankWorld();
      final p = w.players[0];
      expect(
        const ExchangeCmd(0, Res.wood, Res.gold, 100).apply(w),
        CmdResult.notFound,
      );
      addBuilding(w, 'market', 10, 10);
      final wood = p.stock[Res.wood];
      final gold = p.stock[Res.gold];
      expect(
        const ExchangeCmd(0, Res.wood, Res.gold, 100).apply(w),
        CmdResult.ok,
      );
      expect(p.stock[Res.wood], wood - 100);
      expect(p.stock[Res.gold], gold + 80);
      expect(
        const ExchangeCmd(0, Res.wood, Res.wood, 10).apply(w),
        CmdResult.invalid,
      );
      expect(
        const ExchangeCmd(0, Res.wood, Res.gold, 0).apply(w),
        CmdResult.invalid,
      );
      expect(
        const ExchangeCmd(0, Res.wood, Res.gold, 5000).apply(w),
        CmdResult.cannotAfford,
      );
      expect(
        const ExchangeCmd(0, Res.wood, Res.gold, 1).apply(w),
        CmdResult.invalid,
      );
    });
  });

  group('garnison', () {
    test('entrer dans le centre-ville puis ressortir', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      final u = addUnit(w, 'villager', 12, 5);
      w.submit(GarrisonCmd(0, [u.id], tc.id));
      runUntil(w, () => u.state == UnitState.garrisoned, limit: 400);
      expect(tc.garrisoned, [u.id]);
      expectHealthy(w);
      w.submit(MoveCmd(0, [u.id], 20, 20));
      run(w, 3);
      expect(
        u.state,
        UnitState.garrisoned,
        reason: 'ordres ignorés en garnison',
      );
      w.submit(UngarrisonCmd(0, tc.id));
      w.step();
      expect(u.isIdle, isTrue);
      expect(tc.garrisoned, isEmpty);
      expect(w.map.blocked(w.map.index(u.tileX, u.tileY)), isFalse);
      expect(UngarrisonCmd(0, tc.id).apply(w), CmdResult.nothingToDo);
    });

    test('bâtiment détruit : la garnison est éjectée vivante', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      final u = addUnit(w, 'villager', 12, 5);
      w.submit(GarrisonCmd(0, [u.id], tc.id));
      runUntil(w, () => u.state == UnitState.garrisoned, limit: 400);
      w.removeBuilding(tc, destroyed: true);
      run(w, 2);
      expect(u.isIdle, isTrue);
      expect(w.units.containsKey(u.id), isTrue);
      expectHealthy(w);
    });
  });
}
