import 'dart:convert';

import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/systems/combat.dart';
import 'package:age_of_empire_camer/sim/systems/production.dart';
import 'package:age_of_empire_camer/sim/systems/victory.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';
import '../helpers/test_defs.dart';

void _passive(Iterable<Unit> us) {
  for (final u in us) {
    u.stance = Stance.passive;
  }
}

void main() {
  group('dégâts', () {
    test('bonus de catégorie : le lancier frappe fort la cavalerie', () {
      final w = blankWorld();
      w.players[0].age = 2;
      final s = addUnit(w, 'spearman', 5, 5);
      final h = addUnit(w, 'horseman', 6, 5, owner: 1);
      _passive([s, h]);
      w.submit(AttackCmd(0, [s.id], h.id));
      runUntil(w, () => h.hp < h.maxHp);
      // 4 + 12 de bonus − 1 d'armure de mêlée.
      expect(h.maxHp - h.hp, 15);
      expectHealthy(w);
    });

    test(
      'armure à distance : la flèche est réduite par l’armure perforante',
      () {
        final w = blankWorld();
        w.players[0].age = 1;
        final a = addUnit(w, 'archer', 5, 5);
        final t = addUnit(w, 'iron_warrior', 9, 5, owner: 1);
        _passive([a, t]);
        w.submit(AttackCmd(0, [a.id], t.id));
        runUntil(w, () => t.hp < t.maxHp);
        expect(t.maxHp - t.hp, 3); // 5 − 2
        expectHealthy(w);
      },
    );

    test('la flèche arrive avec un délai (projectile en vol)', () {
      final w = blankWorld();
      w.players[0].age = 1;
      final a = addUnit(w, 'archer', 5, 5);
      final t = addUnit(w, 'spearman', 10, 5, owner: 1);
      _passive([a, t]);
      w.submit(AttackCmd(0, [a.id], t.id));
      runUntil(w, () => w.projectiles.isNotEmpty);
      expect(t.hp, t.maxHp, reason: 'pas encore touché');
      runUntil(w, () => t.hp < t.maxHp);
      expect(w.projectiles, isEmpty);
    });

    test('projectile sur cible morte : aucun effet, aucune exception', () {
      final w = blankWorld();
      w.players[0].age = 1;
      final a = addUnit(w, 'archer', 5, 5);
      final t = addUnit(w, 'villager', 10, 5, owner: 1);
      _passive([a, t]);
      w.submit(AttackCmd(0, [a.id], t.id));
      runUntil(w, () => w.projectiles.isNotEmpty);
      w.killUnit(t);
      run(w, 40);
      expect(w.projectiles, isEmpty);
      expectHealthy(w);
    });

    test('hauteur : le tireur en hauteur gagne en dégâts', () {
      final w = blankWorld();
      final a = addUnit(w, 'spearman', 5, 5);
      final t = addUnit(w, 'spearman', 6, 5, owner: 1);
      _passive([a, t]);
      w.map.elevation[w.map.index(5, 5)] = 2;
      w.submit(AttackCmd(0, [a.id], t.id));
      runUntil(w, () => t.hp < t.maxHp);
      // 4 × 125 % = 5 − 1 d'armure perforante… mêlée : armure 0 → 5.
      expect(t.maxHp - t.hp, 5);
    });

    test('recherche d’attaque : +15 % pour l’infanterie', () {
      final w = blankWorld();
      final p = w.players[0]..age = 1;
      p.addTech(testDefs.tech('melee_attack_1'));
      final iw = addUnit(w, 'iron_warrior', 5, 5); // attaque 7
      final t = addUnit(w, 'villager', 6, 5, owner: 1); // armure 0
      _passive([iw, t]);
      w.submit(AttackCmd(0, [iw.id], t.id));
      runUntil(w, () => t.hp < t.maxHp);
      expect(t.maxHp - t.hp, 8); // 7 × 115 / 100 = 8
    });

    test('le bonus de recherche de PV s’applique aux unités existantes', () {
      final w = blankWorld();
      w.players[0].age = 1;
      final s = addUnit(w, 'spearman', 5, 5);
      expect(s.maxHp, 45);
      w.players[0].addTech(testDefs.tech('hp_inf_1'));
      refreshUnitHp(w, 0);
      expect(s.maxHp, 51);
      expect(s.hp, 51);
      final n = addUnit(w, 'spearman', 6, 6);
      expect(n.maxHp, 51);
    });
  });

  group('zone et friendly fire', () {
    test('la catapulte blesse aussi les alliés dans la zone', () {
      final w = blankWorld();
      w.players[0].age = 2;
      final c = addUnit(w, 'catapult', 5, 5);
      final enemy = addUnit(w, 'spearman', 12, 5, owner: 1);
      final friend = addUnit(w, 'spearman', 12, 6);
      _passive([c, enemy, friend]);
      w.submit(AttackCmd(0, [c.id], enemy.id));
      runUntil(w, () => friend.hp < friend.maxHp, limit: 600);
      expect(enemy.hp, lessThan(enemy.maxHp));
      expectHealthy(w);
    });

    test('la catapulte est efficace contre les bâtiments', () {
      final w = blankWorld();
      w.players[0].age = 2;
      final c = addUnit(w, 'catapult', 5, 5);
      final b = addBuilding(w, 'hut', 12, 5, owner: 1);
      w.submit(AttackCmd(0, [c.id], b.id));
      runUntil(w, () => b.hp < b.maxHp, limit: 600);
      expect(b.maxHp - b.hp, 40); // 12 + 28 − 0
    });

    test('effondrement : un bâtiment détruit blesse les unités voisines', () {
      final w = blankWorld();
      final b = addBuilding(w, 'hut', 10, 10, owner: 1);
      final near = addUnit(w, 'villager', 12, 10);
      final far = addUnit(w, 'villager', 20, 20);
      damageBuilding(w, b, 9999, srcOwner: 0);
      expect(w.buildings, isEmpty);
      expect(near.hp, near.maxHp - w.balance.combat.collapseDamage);
      expect(far.hp, far.maxHp);
      expect(w.players[0].stats.buildingsDestroyed, 1);
    });
  });

  group('tours et garnison', () {
    test('une tour tire sur les ennemis ; la garnison ajoute des flèches', () {
      final w = blankWorld();
      w.players[0].age = 1;
      final tower = addBuilding(w, 'tower', 10, 10);
      final foe = addUnit(w, 'spearman', 15, 11, owner: 1);
      foe.stance = Stance.passive;
      runUntil(w, () => w.projectiles.isNotEmpty);
      final before = w.projectiles.length;
      expect(before, 1);
      w.projectiles.clear();
      tower.cooldown = 0;
      for (var i = 0; i < 3; i++) {
        final s = addUnit(w, 'spearman', 12, 9);
        s.stance = Stance.passive;
        tower.garrisoned.add(s.id);
        s.garrisonIn = tower.id;
        s.state = UnitState.garrisoned;
      }
      runUntil(w, () => w.projectiles.isNotEmpty);
      expect(w.projectiles.length, 1 + 3);
    });

    test('une tour ignore les alliés', () {
      final w = blankWorld();
      w.players[0].age = 1;
      addBuilding(w, 'tower', 10, 10);
      final friend = addUnit(w, 'spearman', 12, 11);
      friend.stance = Stance.passive;
      run(w, 80);
      expect(w.projectiles, isEmpty);
      expect(friend.hp, friend.maxHp);
    });
  });

  group('effets', () {
    test('l’étourdissement ne se cumule pas, puis immunité', () {
      final w = blankWorld();
      final u = addUnit(w, 'spearman', 5, 5);
      const stun = EffectSpec(EffectKind.stun, 0, 20);
      addEffect(w, u, stun, 1);
      addEffect(w, u, stun, 2);
      expect(u.effects.where((e) => e.kind == EffectKind.stun).length, 1);
      expect(isStunned(u), isTrue);
      run(w, 21);
      expect(isStunned(u), isFalse);
      addEffect(w, u, stun, 1);
      expect(isStunned(u), isFalse, reason: 'immunité de 3 s');
      run(w, w.balance.combat.stunImmunityTicks + 1);
      addEffect(w, u, stun, 1);
      expect(isStunned(u), isTrue);
    });

    test('un même pouvoir rafraîchit au lieu de se cumuler', () {
      final w = blankWorld();
      final u = addUnit(w, 'spearman', 5, 5);
      addEffect(w, u, const EffectSpec(EffectKind.attackPct, 20, 50), 3);
      run(w, 20);
      addEffect(w, u, const EffectSpec(EffectKind.attackPct, 20, 50), 3);
      expect(u.effects.length, 1);
      expect(u.effects.first.remaining, 50);
      expect(effectSum(u, EffectKind.attackPct), 20);
    });

    test('plafonds : ralentissement −60 %, attaque +100 %', () {
      final w = blankWorld();
      final u = addUnit(w, 'spearman', 5, 5);
      for (var i = 0; i < 5; i++) {
        addEffect(w, u, const EffectSpec(EffectKind.slow, 40, 100), 10 + i);
        addEffect(
          w,
          u,
          const EffectSpec(EffectKind.attackPct, 60, 100),
          20 + i,
        );
      }
      expect(speedPercentOf(w, u), 40);
      expect(attackPercentOf(w, u), 200);
      expect(u.effects.length, lessThanOrEqualTo(w.balance.combat.maxEffects));
    });

    test('mort ⇒ effets purgés', () {
      final w = blankWorld();
      final u = addUnit(w, 'spearman', 5, 5);
      addEffect(w, u, const EffectSpec(EffectKind.slow, 40, 100), 1);
      w.killUnit(u);
      expect(u.effects, isEmpty);
      run(w, 2);
      expectHealthy(w);
    });

    test('dégâts sur la durée : crédités au lanceur, mort gérée', () {
      final w = blankWorld();
      final u = addUnit(w, 'villager', 5, 5, owner: 1);
      u.hp = 8;
      addEffect(w, u, const EffectSpec(EffectKind.dot, 7, 40), 1, srcOwner: 0);
      run(w, 40);
      expect(w.units.containsKey(u.id), isFalse);
      expect(w.players[0].stats.unitsKilled, 1);
      expectHealthy(w);
    });

    test('purge : retire étourdissement, ralentissement et malus', () {
      final w = blankWorld();
      final u = addUnit(w, 'spearman', 5, 5);
      addEffect(w, u, const EffectSpec(EffectKind.stun, 0, 50), 1);
      addEffect(w, u, const EffectSpec(EffectKind.slow, 30, 50), 2);
      addEffect(w, u, const EffectSpec(EffectKind.attackPct, -40, 50), 3);
      addEffect(w, u, const EffectSpec(EffectKind.attackPct, 20, 50), 4);
      addEffect(w, u, const EffectSpec(EffectKind.purge, 0, 0), 5);
      expect(u.effects.length, 1);
      expect(u.effects.single.value, 20);
    });

    test('une unité étourdie ne bouge ni ne frappe', () {
      final w = blankWorld();
      final a = addUnit(w, 'spearman', 5, 5);
      final t = addUnit(w, 'spearman', 6, 5, owner: 1);
      _passive([a, t]);
      addEffect(w, a, const EffectSpec(EffectKind.stun, 0, 30), 1);
      w.submit(AttackCmd(0, [a.id], t.id));
      run(w, 25);
      expect(t.hp, t.maxHp);
      run(w, 40);
      expect(t.hp, lessThan(t.maxHp));
    });
  });

  group('pouvoirs', () {
    test('cible morte entre le clic et l’exécution : pouvoir non consommé', () {
      final w = blankWorld();
      w.players[0].age = 1;
      final iw = addUnit(w, 'iron_warrior', 5, 5);
      final t = addUnit(w, 'spearman', 6, 5, owner: 1);
      final id = t.id;
      w.killUnit(t);
      run(w, 1);
      expect(
        PowerCmd(0, iw.id, 0, target: id).apply(w),
        CmdResult.notFound,
      );
      expect(iw.powerCd[0], 0);
    });

    test('hors de portée : refus, rien de consommé', () {
      final w = blankWorld();
      w.players[0].age = 1;
      final iw = addUnit(w, 'iron_warrior', 5, 5);
      final t = addUnit(w, 'spearman', 20, 5, owner: 1);
      expect(
        PowerCmd(0, iw.id, 0, target: t.id).apply(w),
        CmdResult.outOfRange,
      );
      expect(iw.powerCd[0], 0);
    });

    test(
      'frappe écrasante : étourdit la cible, recharge, pas de réutilisation',
      () {
        final w = blankWorld();
        w.players[0].age = 1;
        final iw = addUnit(w, 'iron_warrior', 5, 5);
        final t = addUnit(w, 'spearman', 6, 5, owner: 1);
        _passive([iw, t]);
        expect(PowerCmd(0, iw.id, 0, target: t.id).apply(w), CmdResult.ok);
        expect(isStunned(t), isTrue);
        expect(t.hp, t.maxHp - 10);
        expect(iw.powerCd[0], 300);
        expect(
          PowerCmd(0, iw.id, 0, target: t.id).apply(w),
          CmdResult.nothingToDo,
        );
      },
    );

    test('âge insuffisant : verrouillé', () {
      final w = blankWorld();
      final a = addUnit(w, 'archer', 5, 5);
      expect(
        PowerCmd(0, a.id, 0, x: 8, y: 5).apply(w),
        CmdResult.locked,
      );
    });

    test('mur de lances : armure, immobilisation (peut encore frapper)', () {
      final w = blankWorld();
      final s = addUnit(w, 'spearman', 5, 5);
      expect(PowerCmd(0, s.id, 0).apply(w), CmdResult.ok);
      expect(isRooted(s), isTrue);
      expect(unitArmor(w, s, DamageType.melee), 3);
      w.submit(MoveCmd(0, [s.id], 20, 5));
      run(w, 20);
      expect(s.tileX, 5, reason: 'enraciné');
      expectHealthy(w);
    });

    test('pluie de flèches : dégâts sur la durée en zone, ennemis seuls', () {
      final w = blankWorld();
      w.players[0].age = 1;
      final a = addUnit(w, 'archer', 5, 5);
      final e1 = addUnit(w, 'spearman', 10, 5, owner: 1);
      final e2 = addUnit(w, 'spearman', 10, 6, owner: 1);
      final friend = addUnit(w, 'spearman', 10, 4);
      _passive([a, e1, e2, friend]);
      expect(PowerCmd(0, a.id, 0, x: 10, y: 5).apply(w), CmdResult.ok);
      run(w, 40);
      expect(e1.hp, lessThan(e1.maxHp));
      expect(e2.hp, lessThan(e2.maxHp));
      expect(friend.hp, friend.maxHp);
    });

    test('charge : premier coup doublé', () {
      final w = blankWorld();
      w.players[0].age = 2;
      final h = addUnit(w, 'horseman', 5, 5);
      final t = addUnit(w, 'villager', 6, 5, owner: 1);
      _passive([h, t]);
      expect(PowerCmd(0, h.id, 0).apply(w), CmdResult.ok);
      w.submit(AttackCmd(0, [h.id], t.id));
      runUntil(w, () => t.hp < t.maxHp);
      expect(t.maxHp - t.hp, 12); // 6 × 200 %
      final first = t.hp;
      runUntil(w, () => t.hp < first || !t.alive);
      expect(first - (t.alive ? t.hp : 0), 6);
    });

    test('toutes les unités et tous les pouvoirs déclarés sont lançables', () {
      var covered = 0;
      for (final def in testDefs.units) {
        for (var slot = 0; slot < def.powers.length; slot++) {
          final pd = testDefs.power(def.powers[slot]);
          if (pd.aura) continue;
          final w = blankWorld();
          w.players[0].age = 3;
          final caster = addUnit(w, def.id, 10, 10);
          final foe = addUnit(w, 'spearman', 12, 10, owner: 1);
          final ally = addUnit(w, 'spearman', 11, 11);
          _passive([foe, ally]);
          final cmd = PowerCmd(
            0,
            caster.id,
            slot,
            x: 12,
            y: 10,
            target: pd.target == PowerTarget.unit ? foe.id : -1,
          );
          expect(cmd.apply(w), CmdResult.ok, reason: '${def.id}/${pd.id}');
          expect(caster.powerCd[slot], pd.cooldownTicks);
          run(w, 100);
          expectHealthy(w);
          covered++;
        }
      }
      expect(covered, greaterThanOrEqualTo(15));
    });

    test('les auras s’appliquent aux alliés proches, sans cumul', () {
      final w = blankWorld();
      w.players[0].age = 2;
      addUnit(w, 'hero_mbarga', 10, 10);
      final ally = addUnit(w, 'spearman', 12, 10);
      final foe = addUnit(w, 'spearman', 13, 10, owner: 1);
      _passive([ally, foe]);
      run(w, 45);
      expect(effectSum(ally, EffectKind.attackPct), 5);
      expect(ally.effects.length, 1);
      expect(foe.effects, isEmpty);
    });
  });

  group('sorts de bataille et tambour', () {
    test('le tambour se remplit en infligeant des dégâts', () {
      final w = blankWorld();
      final a = addUnit(w, 'spearman', 5, 5);
      final t = addUnit(w, 'villager', 6, 5, owner: 1);
      _passive([a, t]);
      expect(w.players[0].drum, 0);
      w.submit(AttackCmd(0, [a.id], t.id));
      runUntil(w, () => w.players[0].drum > 0);
    });

    test('foudre : coût en énergie, recharge, dégâts de zone sur ennemis', () {
      final w = blankWorld();
      final e = addUnit(w, 'iron_warrior', 10, 10, owner: 1);
      final f = addUnit(w, 'spearman', 10, 11);
      _passive([e, f]);
      final idx = testDefs.power('lightning').index;
      expect(SpellCmd(0, idx, 10, 10).apply(w), CmdResult.cannotAfford);
      w.players[0].drum = 1000;
      expect(SpellCmd(0, idx, 10, 10).apply(w), CmdResult.ok);
      expect(w.players[0].drum, greaterThanOrEqualTo(700));
      expect(e.hp, e.maxHp - 50);
      expect(f.hp, f.maxHp);
      expect(SpellCmd(0, idx, 10, 10).apply(w), CmdResult.nothingToDo);
    });

    test('un pouvoir d’unité ne se lance pas comme un sort', () {
      final w = blankWorld();
      final idx = testDefs.power('rally_cry').index;
      expect(SpellCmd(0, idx, 5, 5).apply(w), CmdResult.wrongTarget);
    });

    test('soin et rage touchent les alliés', () {
      final w = blankWorld();
      final f = addUnit(w, 'spearman', 10, 10)..hp = 10;
      w.players[0].drum = 1000;
      expect(
        SpellCmd(0, testDefs.power('heal_spell').index, 10, 10).apply(w),
        CmdResult.ok,
      );
      expect(f.hp, 45);
      expect(
        SpellCmd(0, testDefs.power('rage').index, 10, 10).apply(w),
        CmdResult.ok,
      );
      expect(effectSum(f, EffectKind.attackPct), 40);
    });
  });

  group('âges', () {
    test('changement d’âge : conditions, coût, temps, déblocages', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      expect(
        AgeUpCmd(0, tc.id).apply(w),
        CmdResult.locked,
        reason: 'prérequis',
      );
      addBuilding(w, 'hut', 12, 5);
      addBuilding(w, 'granary', 15, 5);
      final before = w.players[0].stock.copy();
      expect(AgeUpCmd(0, tc.id).apply(w), CmdResult.ok);
      expect(w.players[0].stock.v[0], before.v[0] - 500);
      expect(
        AgeUpCmd(0, tc.id).apply(w),
        CmdResult.nothingToDo,
        reason: 'une seule recherche d’âge à la fois',
      );
      expect(w.players[0].age, 0);
      runUntil(w, () => w.players[0].age == 1, limit: 500);
      // Débloque l'archer.
      expect(
        TrainCmd(0, addBuilding(w, 'barracks', 20, 20).id, 'archer').apply(w),
        CmdResult.ok,
      );
      expectHealthy(w);
    });

    test('annuler la recherche d’âge rembourse exactement', () {
      final w = blankWorld();
      final tc = addBuilding(w, 'town_center', 5, 5);
      addBuilding(w, 'hut', 12, 5);
      addBuilding(w, 'granary', 15, 5);
      final before = w.players[0].stock.copy();
      AgeUpCmd(0, tc.id).apply(w);
      expect(CancelQueueCmd(0, tc.id, 0).apply(w), CmdResult.ok);
      expect(w.players[0].stock, before);
    });

    test('âge II → III se fait au Palais', () {
      final w = blankWorld();
      w.players[0].age = 1;
      final tc = addBuilding(w, 'town_center', 5, 5);
      addBuilding(w, 'palace', 20, 20);
      addBuilding(w, 'barracks', 30, 20);
      addBuilding(w, 'forge', 30, 30);
      expect(AgeUpCmd(0, tc.id).apply(w), CmdResult.wrongTarget);
      final palace = w.buildings.values.firstWhere((b) => b.def.id == 'palace');
      expect(AgeUpCmd(0, palace.id).apply(w), CmdResult.ok);
      runUntil(w, () => w.players[0].age == 2, limit: 700);
    });
  });

  group('héros', () {
    test('un seul héros à la fois, verrouillé par clan', () {
      final w = blankWorld();
      final p = w.players[0]
        ..age = 2
        ..clan = testDefs.clan('fleuve').index;
      final altar = addBuilding(w, 'altar', 10, 10);
      expect(
        TrainCmd(0, altar.id, 'hero_ngolo').apply(w),
        CmdResult.locked,
        reason: 'héros d’un autre clan',
      );
      expect(TrainCmd(0, altar.id, 'hero_mbarga').apply(w), CmdResult.ok);
      expect(
        TrainCmd(0, altar.id, 'hero_mbarga').apply(w),
        CmdResult.nothingToDo,
      );
      expect(p.popUsed, 0);
      addBuilding(w, 'hut', 20, 20);
      addBuilding(w, 'hut', 23, 20);
      w.players[0].popCap = 0;
      runUntil(
        w,
        () => w.units.values.any((u) => u.def.isHero),
        limit: 800,
      );
      expectHealthy(w);
    });

    test('la résurrection coûte plus cher à chaque mort', () {
      final w = blankWorld();
      final p = w.players[0]
        ..age = 2
        ..clan = testDefs.clan('fleuve').index;
      final hero = testDefs.unit('hero_mbarga');
      final c0 = unitCostFor(w, p, hero);
      expect(c0, hero.cost);
      p.fallenHeroes.add(hero.index);
      final c1 = unitCostFor(w, p, hero);
      expect(c1.v[0], greaterThan(c0.v[0]));
      p.fallenHeroes.add(hero.index);
      final c2 = unitCostFor(w, p, hero);
      expect(c2.v[4], greaterThan(c1.v[4]));
    });

    test('la mort du héros est comptée et purge ses effets', () {
      final w = blankWorld();
      final h = addUnit(w, 'hero_mbarga', 5, 5);
      damageUnit(w, h, 9999, srcOwner: 1);
      run(w, 1);
      expect(w.players[0].fallenHeroes, [h.def.index]);
      expect(w.players[0].stats.heroDeaths, 1);
      expect(w.players[1].stats.unitsKilled, 1);
    });
  });

  group('victoire et défaite', () {
    World duel() {
      final w = blankWorld();
      w.victoryMode = VictoryMode.conquest;
      addBuilding(w, 'town_center', 5, 5);
      addBuilding(w, 'town_center', 30, 30, owner: 1);
      addUnit(w, 'villager', 9, 9);
      addUnit(w, 'villager', 28, 28, owner: 1);
      return w;
    }

    test('conquête : détruire le dernier bâtiment vital fait gagner', () {
      final w = duel();
      run(w, 20);
      expect(w.gameOver, isFalse);
      final tc = w.buildings.values.firstWhere((b) => b.owner == 1);
      damageBuilding(w, tc, 99999, srcOwner: 0);
      run(w, w.balance.combat.straggleSeconds * 10 + 20);
      expect(w.players[1].defeated, isTrue);
      expect(w.gameOver, isTrue);
      expect(w.winnerTeam, w.players[0].team);
      expect(w.units.values.where((u) => u.owner == 1), isEmpty);
      expectHealthy(w);
    });

    test('reddition', () {
      final w = duel();
      w.submit(const ResignCmd(0));
      run(w, 20);
      expect(w.winnerTeam, w.players[1].team);
    });

    test('égalité si les deux tombent au même tick', () {
      final w = duel();
      w.submit(const ResignCmd(0));
      w.submit(const ResignCmd(1));
      run(w, 20);
      expect(w.winnerTeam, -2);
    });

    test('sans bâtiment mais avec villageois : survit jusqu’au délai', () {
      final w = duel();
      final tc = w.buildings.values.firstWhere((b) => b.owner == 1);
      w.removeBuilding(tc, destroyed: true);
      run(w, 100);
      expect(w.players[1].defeated, isFalse);
      run(w, w.balance.combat.straggleSeconds * 10);
      expect(w.players[1].defeated, isTrue);
    });

    test('sans bâtiment ni villageois : éliminé tout de suite', () {
      final w = duel();
      final tc = w.buildings.values.firstWhere((b) => b.owner == 1);
      w.removeBuilding(tc, destroyed: true);
      for (final u in w.unitsOf(1)) {
        w.killUnit(u);
      }
      run(w, 20);
      expect(w.players[1].defeated, isTrue);
    });

    test('alliance : une équipe de deux joueurs gagne ensemble', () {
      final w = blankWorld(players: 3);
      w.victoryMode = VictoryMode.conquest;
      w.players[1].team = w.players[0].team;
      addBuilding(w, 'town_center', 5, 5);
      addBuilding(w, 'town_center', 12, 5, owner: 1);
      final enemy = addBuilding(w, 'town_center', 30, 30, owner: 2);
      final friendUnit = addUnit(w, 'spearman', 10, 12, owner: 1);
      final mine = addUnit(w, 'spearman', 10, 13);
      expect(isEnemyTargetOf(w, 0, friendUnit.id), isFalse);
      damageBuilding(w, enemy, 99999, srcOwner: 0);
      run(w, w.balance.combat.straggleSeconds * 10 + 20);
      expect(w.gameOver, isTrue);
      expect(w.winnerTeam, w.players[0].team);
      expect(mine.alive, isTrue);
    });

    test('sans règle de victoire (tests) : jamais de fin de partie', () {
      final w = blankWorld();
      run(w, 50);
      expect(w.gameOver, isFalse);
      expect(w.players.every((p) => !p.defeated), isTrue);
    });
  });

  group('acquisition, poursuite, abandon', () {
    test('un soldat agressif attaque seul les ennemis en vue', () {
      final w = blankWorld();
      final a = addUnit(w, 'spearman', 5, 5);
      final t = addUnit(w, 'villager', 9, 5, owner: 1);
      t.stance = Stance.passive;
      runUntil(w, () => !t.alive, limit: 600);
      expect(a.alive, isTrue);
    });

    test('abandon : la poursuite automatique s’arrête hors de la laisse', () {
      final w = blankWorld(size: 80);
      final a = addUnit(w, 'spearman', 5, 5);
      final runner = addUnit(w, 'horseman', 11, 5, owner: 1);
      w.players[1].age = 2;
      runner.stance = Stance.passive;
      runUntil(w, () => a.order?.kind == OrderKind.attack, limit: 100);
      // La cible s'enfuit loin, plus vite que le poursuivant.
      w.submit(MoveCmd(1, [runner.id], 70, 5));
      var returned = false;
      for (var i = 0; i < 600; i++) {
        w.step();
        if (!a.leashed && a.order?.kind == OrderKind.move) returned = true;
      }
      expect(returned || a.tileX < 20, isTrue);
      expect(a.tileX, lessThan(30));
      expectHealthy(w);
    });

    test('les murs ne sont pas des cibles automatiques', () {
      final w = blankWorld();
      w.players[1].age = 1;
      addBuilding(w, 'wall', 7, 5, owner: 1);
      final a = addUnit(w, 'spearman', 5, 5);
      run(w, 100);
      expect(a.isIdle, isTrue);
    });

    test('un mur peut être détruit sur ordre', () {
      final w = blankWorld();
      w.players[1].age = 1;
      final wall = addBuilding(w, 'wall', 7, 5, owner: 1);
      final c = addUnit(w, 'catapult', 3, 5);
      w.players[0].age = 2;
      w.submit(AttackCmd(0, [c.id], wall.id));
      runUntil(w, () => !w.buildings.containsKey(wall.id), limit: 2000);
    });
  });

  group('sauvegarde', () {
    test('projectiles, effets, recharges : aller-retour identique', () {
      final w = blankWorld();
      w.players[0]
        ..age = 2
        ..drum = 321
        ..fallenHeroes.add(testDefs.unit('hero_mbarga').index);
      final a = addUnit(w, 'archer', 5, 5);
      final t = addUnit(w, 'spearman', 10, 5, owner: 1);
      _passive([a, t]);
      addEffect(
        w,
        t,
        const EffectSpec(EffectKind.slow, 30, 80),
        4,
        srcOwner: 0,
      );
      w.submit(AttackCmd(0, [a.id], t.id));
      runUntil(w, () => w.projectiles.isNotEmpty);
      final h1 = w.stateHash();
      final copy = World.fromJson(
        testDefs,
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
      );
      expect(copy.stateHash(), h1);
      run(w, 120);
      run(copy, 120);
      expect(copy.stateHash(), w.stateHash());
    });
  });
}

bool isEnemyTargetOf(World w, int owner, int id) =>
    w.units[id] != null && hostile(w, owner, w.units[id]!.owner);
