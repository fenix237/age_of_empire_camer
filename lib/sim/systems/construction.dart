import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/production.dart';
import 'package:age_of_empire_camer/sim/systems/unit_system.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Valide l'emplacement d'un bâtiment (sans effet de bord).
CmdResult validatePlacement(
  World w,
  int owner,
  BuildingDef def,
  int tx,
  int ty,
) {
  final m = w.map;
  final p = w.players[owner];
  if (def.age > p.age) return CmdResult.locked;
  for (final req in def.requires) {
    final has = w.buildings.values.any(
      (b) => b.owner == owner && b.complete && b.def.id == req,
    );
    if (!has) return CmdResult.locked;
  }
  for (var y = ty; y < ty + def.height; y++) {
    for (var x = tx; x < tx + def.width; x++) {
      if (!m.inBounds(x, y)) return CmdResult.badPlacement;
      final i = m.index(x, y);
      if (m.occupant[i] != 0 || !m.terrainDef(i).buildable) {
        return CmdResult.badPlacement;
      }
      if (p.explored[i] == 0) return CmdResult.unexplored;
    }
  }
  // Une unité ennemie sur l'emplacement interdit la pose.
  for (final u in w.units.values) {
    if (!u.alive || u.owner == owner || u.state == UnitState.garrisoned) {
      continue;
    }
    if (u.tileX >= tx &&
        u.tileX < tx + def.width &&
        u.tileY >= ty &&
        u.tileY < ty + def.height) {
      return CmdResult.badPlacement;
    }
  }
  return CmdResult.ok;
}

/// Pose un bâtiment en construction, paie le coût et envoie les bâtisseurs.
CmdResult placeBuilding(
  World w,
  int owner,
  BuildingDef def,
  int tx,
  int ty,
  List<Unit> builders, {
  required bool queue,
}) {
  final r = validatePlacement(w, owner, def, tx, ty);
  if (r != CmdResult.ok) return r;
  final p = w.players[owner];
  if (!p.stock.covers(def.cost)) return CmdResult.cannotAfford;
  p.stock.subtract(def.cost);
  final b = w.spawnBuilding(def, owner, tx, ty);
  _evictUnits(w, b);
  for (final u in builders) {
    issueOrder(w, u, Order.build(b.id), queue: queue);
  }
  return CmdResult.ok;
}

/// Repousse les unités se trouvant sur l'emprise du nouveau bâtiment.
void _evictUnits(World w, Building b) {
  for (final u in w.units.values) {
    if (!u.alive || u.state == UnitState.garrisoned) continue;
    if (!b.coversTile(u.tileX, u.tileY)) continue;
    final spot = freeSpawnTile(w, b, u.tileX, u.tileY);
    if (spot != null) {
      u.x = Fx.tileCenter(spot.x);
      u.y = Fx.tileCenter(spot.y);
      u.px = u.x;
      u.py = u.y;
    }
    u.clearPath();
    if (u.orders.isNotEmpty && u.state != UnitState.idle) {
      beginOrder(w, u);
    }
  }
}

/// Suppression volontaire. En construction : remboursement proportionnel au
/// restant. Terminé : aucun remboursement. Les files sont remboursées.
void deleteBuilding(World w, Building b) {
  final p = w.players[b.owner];
  if (!b.complete) {
    final total = b.totalBuildMilli;
    final left = (total - b.progressMilli).clamp(0, total);
    p.stock.add(b.def.cost.scaled(left, total));
  }
  for (final q in b.queue) {
    p.stock.add(q.paid.scaled(w.balance.queueRefundPercent, 100));
  }
  b.queue.clear();
  w.removeBuilding(b, destroyed: false);
}

/// Remplit à nouveau un champ vide en payant du bois.
bool reseedField(World w, Building b) {
  if (!b.isField || b.stock > 0) return false;
  final p = w.players[b.owner];
  final cost = w.balance.reseedCostWood;
  if (p.stock[Res.wood] < cost) return false;
  p.stock[Res.wood] -= cost;
  b.stock = b.def.fieldFood;
  return true;
}

/// Applique la progression de construction (fin de tick, ordre d'id).
void finishConstruction(World w) {
  final speeds = w.balance.buildSpeedMilli;
  for (final b in w.buildings.values) {
    final n = b.buildersThisTick;
    b.buildersThisTick = 0;
    if (n == 0 || b.complete) continue;
    final mult = speeds[n >= speeds.length ? speeds.length - 1 : n];
    final total = b.totalBuildMilli;
    final before = b.progressMilli;
    b.progressMilli = (before + mult).clamp(0, total);
    final gain = b.maxHp * b.progressMilli ~/ total - b.maxHp * before ~/ total;
    b.hp = (b.hp + gain).clamp(1, b.maxHp);
    if (b.progressMilli >= total) {
      b
        ..complete = true
        ..hp = b.hp.clamp(1, b.maxHp);
      w.events.add(
        GameEvent(EventType.buildingComplete, b.owner, b.id, b.tx, b.ty),
      );
    }
  }
}
