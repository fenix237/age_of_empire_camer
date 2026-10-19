import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/combat.dart';
import 'package:age_of_empire_camer/sim/systems/economy.dart';
import 'package:age_of_empire_camer/sim/systems/unit_system.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/player.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Case libre adjacente au bâtiment, la plus proche de (tx, ty) (ou du
/// centre du bâtiment si négatif). Anneaux de 1 à 4 cases.
({int x, int y})? freeSpawnTile(World w, Building b, int tx, int ty) {
  final m = w.map;
  final cx = tx >= 0 ? tx : b.tx + b.def.width ~/ 2;
  final cy = ty >= 0 ? ty : b.ty + b.def.height ~/ 2;
  for (var ring = 1; ring <= 4; ring++) {
    ({int x, int y})? best;
    var bestD = 1 << 60;
    for (var y = b.ty - ring; y < b.ty + b.def.height + ring; y++) {
      for (var x = b.tx - ring; x < b.tx + b.def.width + ring; x++) {
        final onRing =
            x < b.tx - ring + 1 ||
            x >= b.tx + b.def.width + ring - 1 ||
            y < b.ty - ring + 1 ||
            y >= b.ty + b.def.height + ring - 1;
        if (!onRing) continue;
        if (!m.inBounds(x, y) || m.blocked(m.index(x, y))) continue;
        final dx = x - cx;
        final dy = y - cy;
        final d = dx * dx + dy * dy;
        if (d < bestD) {
          bestD = d;
          best = (x: x, y: y);
        }
      }
    }
    if (best != null) return best;
  }
  return null;
}

CmdResult enqueueTrain(World w, int owner, int buildingId, String unitId) {
  final b = w.buildings[buildingId];
  if (b == null) return CmdResult.notFound;
  if (b.owner != owner) return CmdResult.notOwned;
  if (!b.complete) return CmdResult.notComplete;
  if (!b.def.trains.contains(unitId)) return CmdResult.wrongTarget;
  final def = w.defs.unit(unitId);
  final p = w.players[owner];
  if (p.defeated) return CmdResult.nothingToDo;
  if (def.age > p.age || p.locked.contains(def.id)) return CmdResult.locked;
  if (def.clan.isNotEmpty &&
      (p.clan < 0 || w.defs.clans[p.clan].id != def.clan)) {
    return CmdResult.locked;
  }
  if (b.queue.length >= w.balance.maxQueue) return CmdResult.queueFull;
  final cost = unitCostFor(w, p, def);
  if (def.isHero) {
    // Un seul héros vivant (ou en file) par joueur.
    for (final u in w.units.values) {
      if (u.owner == owner && u.alive && u.def.isHero) {
        return CmdResult.nothingToDo;
      }
    }
    for (final other in w.buildings.values) {
      if (other.owner != owner) continue;
      for (final q in other.queue) {
        if (!q.isTech && !q.isAge && w.defs.units[q.defIndex].isHero) {
          return CmdResult.nothingToDo;
        }
      }
    }
  }
  if (!p.stock.covers(cost)) return CmdResult.cannotAfford;
  p.stock.subtract(cost);
  b.queue.add(
    QueueItem(
      isTech: false,
      defIndex: def.index,
      remaining: def.trainSeconds * 10,
      paid: cost.copy(),
    ),
  );
  return CmdResult.ok;
}

/// Coût d'entraînement : un héros tombé coûte plus cher à chaque mort.
Stock unitCostFor(World w, Player p, UnitDef def) {
  if (!def.isHero) return def.cost;
  final deaths = p.fallenHeroes.where((i) => i == def.index).length;
  if (deaths == 0) return def.cost;
  final step = w.balance.combat.heroReviveCostPercent - 100;
  final pct = 100 + (deaths > 5 ? 5 : deaths) * step;
  return def.cost.scaled(pct, 100);
}

/// Lance la recherche du prochain âge dans un bâtiment adapté.
CmdResult enqueueAgeUp(World w, int owner, int buildingId) {
  final b = w.buildings[buildingId];
  if (b == null) return CmdResult.notFound;
  if (b.owner != owner) return CmdResult.notOwned;
  if (!b.complete) return CmdResult.notComplete;
  final p = w.players[owner];
  if (p.defeated) return CmdResult.nothingToDo;
  final next = p.age + 1;
  if (next >= w.defs.ages.length) return CmdResult.nothingToDo;
  final age = w.defs.ages[next];
  if (!b.def.agesUp || !age.researchedAt.contains(b.def.id)) {
    return CmdResult.wrongTarget;
  }
  if (b.queue.length >= w.balance.maxQueue) return CmdResult.queueFull;
  for (final other in w.buildings.values) {
    if (other.owner != owner) continue;
    for (final q in other.queue) {
      if (q.isAge) return CmdResult.nothingToDo;
    }
  }
  for (final req in age.requiresBuildings) {
    final has = w.buildings.values.any(
      (x) => x.owner == owner && x.complete && x.def.id == req,
    );
    if (!has) return CmdResult.locked;
  }
  if (!p.stock.covers(age.cost)) return CmdResult.cannotAfford;
  p.stock.subtract(age.cost);
  b.queue.add(
    QueueItem(
      isTech: false,
      isAge: true,
      defIndex: next,
      remaining: age.researchSeconds * 10,
      paid: age.cost.copy(),
    ),
  );
  return CmdResult.ok;
}

CmdResult enqueueResearch(World w, int owner, int buildingId, String techId) {
  final b = w.buildings[buildingId];
  if (b == null) return CmdResult.notFound;
  if (b.owner != owner) return CmdResult.notOwned;
  if (!b.complete) return CmdResult.notComplete;
  if (!b.def.researches.contains(techId)) return CmdResult.wrongTarget;
  final def = w.defs.tech(techId);
  final p = w.players[owner];
  if (p.hasTech(def.index)) return CmdResult.nothingToDo;
  if (def.age > p.age || p.locked.contains(def.id)) return CmdResult.locked;
  if (b.queue.length >= w.balance.maxQueue) return CmdResult.queueFull;
  // Déjà en file quelque part ?
  for (final other in w.buildings.values) {
    if (other.owner != owner) continue;
    for (final q in other.queue) {
      if (q.isTech && q.defIndex == def.index) return CmdResult.nothingToDo;
    }
  }
  if (!p.stock.covers(def.cost)) return CmdResult.cannotAfford;
  p.stock.subtract(def.cost);
  b.queue.add(
    QueueItem(
      isTech: true,
      defIndex: def.index,
      remaining: def.researchSeconds * 10,
      paid: def.cost.copy(),
    ),
  );
  return CmdResult.ok;
}

CmdResult cancelQueueItem(World w, int owner, int buildingId, int index) {
  final b = w.buildings[buildingId];
  if (b == null) return CmdResult.notFound;
  if (b.owner != owner) return CmdResult.notOwned;
  if (index < 0 || index >= b.queue.length) return CmdResult.invalid;
  final q = b.queue.removeAt(index);
  w.players[owner].stock.add(q.paid.scaled(w.balance.queueRefundPercent, 100));
  return CmdResult.ok;
}

/// Avance les files de production (ordre d'identifiant de bâtiment).
void updateProduction(World w) {
  for (final b in w.buildings.values) {
    if (!b.complete || b.queue.isEmpty) continue;
    final item = b.queue.first;
    if (item.remaining > 0) item.remaining--;
    if (item.remaining > 0) continue;
    final p = w.players[b.owner];
    if (item.isAge) {
      p.age = item.defIndex;
      b.queue.removeAt(0);
      w.events.add(GameEvent(EventType.ageAdvanced, b.owner, b.id));
      continue;
    }
    if (item.isTech) {
      final def = w.defs.techs[item.defIndex];
      p.addTech(def);
      p.stats.researches++;
      refreshUnitHp(w, b.owner);
      b.queue.removeAt(0);
      w.events.add(GameEvent(EventType.researchDone, b.owner, b.id));
      continue;
    }
    final def = w.defs.units[item.defIndex];
    // Plafond de population : la production attend de la place.
    if (p.popUsed + def.pop > p.popCap) continue;
    final spot = freeSpawnTile(w, b, b.rallyX, b.rallyY);
    if (spot == null) continue;
    b.queue.removeAt(0);
    p.stats.unitsTrained++;
    final u = w.spawnUnit(
      def,
      b.owner,
      Fx.tileCenter(spot.x),
      Fx.tileCenter(spot.y),
    );
    w.events.add(
      GameEvent(EventType.unitTrained, b.owner, u.id, spot.x, spot.y),
    );
    _applyRally(w, b, u);
  }
}

void _applyRally(World w, Building b, Unit u) {
  if (b.rallyTarget >= 0 && w.exists(b.rallyTarget)) {
    final t = b.rallyTarget;
    if (u.def.villager && canGatherFrom(w, u.owner, t)) {
      issueOrder(w, u, Order.gather(t), queue: false);
      return;
    }
    if (u.def.attack > 0 && isEnemyTarget(w, u.owner, t)) {
      issueOrder(w, u, Order.attack(t), queue: false);
      return;
    }
    final tb = w.buildings[t];
    if (tb != null &&
        tb.owner == u.owner &&
        tb.complete &&
        tb.def.garrison > 0) {
      issueOrder(w, u, Order.garrison(t), queue: false);
      return;
    }
  }
  if (b.rallyX >= 0) {
    issueOrder(w, u, Order.move(b.rallyX, b.rallyY), queue: false);
  }
}

/// Coût total remboursable des files d'un bâtiment (invariant 6).
Stock queuePaidTotal(Building b) {
  final s = Stock();
  for (final q in b.queue) {
    s.add(q.paid);
  }
  return s;
}
