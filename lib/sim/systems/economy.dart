import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Source de ressource récoltable (nœud ou champ).
class Source {
  const Source(this.res, this.amount, this.rect);

  final Res res;
  final int amount;

  /// x, y, largeur, hauteur en cases.
  final List<int> rect;
}

Source? sourceOf(World w, int owner, int id) {
  final n = w.nodes[id];
  if (n != null) {
    return Source(n.res, n.amount, <int>[n.tx, n.ty, 1, 1]);
  }
  final b = w.buildings[id];
  if (b != null && b.isField && b.complete && b.owner == owner) {
    return Source(Res.food, b.stock, <int>[
      b.tx,
      b.ty,
      b.def.width,
      b.def.height,
    ]);
  }
  return null;
}

/// Prélève une unité de ressource ; renvoie la quantité restante.
int takeFromSource(World w, int id) {
  final n = w.nodes[id];
  if (n != null) {
    n.amount--;
    if (n.amount <= 0) w.removeNode(n);
    return n.amount;
  }
  final b = w.buildings[id];
  return b == null ? 0 : --b.stock;
}

bool canGatherFrom(World w, int owner, int id) {
  if (w.nodes.containsKey(id)) return true;
  final b = w.buildings[id];
  return b != null && b.owner == owner && b.isField && b.complete;
}

bool isEnemyTarget(World w, int owner, int id) {
  final u = w.units[id];
  if (u != null) {
    return u.alive && u.owner != owner && u.state != UnitState.garrisoned;
  }
  final b = w.buildings[id];
  return b != null && b.owner != owner;
}

/// Source la plus proche de même type que [resIndex] autour de la dernière
/// cible (rayon d'inactivité). Renvoie -1 s'il n'y en a pas.
int findNextSource(World w, Unit u, int resIndex) {
  if (resIndex < 0) return -1;
  final res = Res.values[resIndex];
  final radius = w.balance.idleSearchRadius;
  final ox = u.lastTargetX;
  final oy = u.lastTargetY;
  var best = -1;
  var bestD = 1 << 60;
  void consider(int id, int tx, int ty, int ww, int hh) {
    if ((tx - ox).abs() > radius + ww || (ty - oy).abs() > radius + hh) return;
    final d = World.distToRect(u.x, u.y, tx, ty, ww, hh);
    if (d < bestD || (d == bestD && id < best)) {
      bestD = d;
      best = id;
    }
  }

  for (final n in w.nodes.values) {
    if (n.res == res && n.amount > 0 && n.id != u.targetId) {
      consider(n.id, n.tx, n.ty, 1, 1);
    }
  }
  if (res == Res.food) {
    for (final b in w.buildings.values) {
      if (b.isField &&
          b.complete &&
          b.owner == u.owner &&
          b.stock > 0 &&
          b.id != u.targetId &&
          gatherersOnField(w, b.id, u.id) < w.balance.fieldGatherers) {
        consider(b.id, b.tx, b.ty, b.def.width, b.def.height);
      }
    }
  }
  return best;
}

int gatherersOnField(World w, int fieldId, int exceptUnit) {
  var n = 0;
  for (final u in w.units.values) {
    if (u.id != exceptUnit &&
        u.targetId == fieldId &&
        u.state == UnitState.gathering) {
      n++;
    }
  }
  return n;
}

/// Dépôt du joueur le plus proche acceptant [res].
Building? nearestDropOff(World w, Unit u, Res res, {int? exclude}) {
  Building? best;
  var bestD = 1 << 60;
  for (final b in w.buildings.values) {
    if (b.owner != u.owner || !b.complete || b.id == exclude) continue;
    if (!b.def.dropOff.contains(res)) continue;
    final d = World.distToRect(u.x, u.y, b.tx, b.ty, b.def.width, b.def.height);
    if (d < bestD) {
      bestD = d;
      best = b;
    }
  }
  return best;
}

/// Après une construction : un bâtisseur d'un dépôt se met à récolter à
/// proximité ; un champ est travaillé directement.
Order? autoWorkAfterBuild(World w, Unit u, Building b) {
  if (b.isField &&
      b.stock > 0 &&
      gatherersOnField(w, b.id, u.id) < w.balance.fieldGatherers) {
    return Order.gather(b.id);
  }
  if (b.def.dropOff.isEmpty) return null;
  final cx = Fx.toInt(b.center.x);
  final cy = Fx.toInt(b.center.y);
  var best = -1;
  var bestD = 1 << 60;
  for (final n in w.nodes.values) {
    if (!b.def.dropOff.contains(n.res) || n.amount <= 0) continue;
    final dx = n.tx - cx;
    final dy = n.ty - cy;
    if (dx.abs() > 8 || dy.abs() > 8) continue;
    final d = dx * dx + dy * dy;
    if (d < bestD) {
      bestD = d;
      best = n.id;
    }
  }
  return best >= 0 ? Order.gather(best) : null;
}

/// Un pas de réparation. Renvoie false si la réparation doit s'arrêter
/// (bâtiment réparé ou ressources insuffisantes).
bool repairStep(World w, Unit u, Building b) {
  final bal = w.balance;
  final p = w.players[u.owner];
  if (b.hp >= b.maxHp) return false;
  u.gatherProgress +=
      b.maxHp * 1000 * bal.repairSpeedPercent ~/ (100 * b.def.buildTicks);
  while (u.gatherProgress >= 1000 && b.hp < b.maxHp) {
    final need = Stock();
    final newDebt = List<int>.of(b.repairDebt);
    for (final r in Res.values) {
      newDebt[r.index] += b.def.cost[r] * bal.repairCostPercent * 10 ~/ b.maxHp;
      need[r] = newDebt[r.index] ~/ 1000;
      newDebt[r.index] -= need[r] * 1000;
    }
    if (!p.stock.covers(need)) {
      u.gatherProgress = 0;
      return false;
    }
    p.stock.subtract(need);
    for (var i = 0; i < newDebt.length; i++) {
      b.repairDebt[i] = newDebt[i];
    }
    b.hp++;
    u.gatherProgress -= 1000;
  }
  return b.hp < b.maxHp;
}

/// Échange au marché : on donne [amount], on reçoit moins (frais en %).
CmdResult exchangeResources(World w, int owner, Res from, Res to, int amount) {
  if (from == to || amount <= 0) return CmdResult.invalid;
  var hasMarket = false;
  for (final b in w.buildings.values) {
    if (b.owner == owner && b.complete && b.def.market) {
      hasMarket = true;
      break;
    }
  }
  if (!hasMarket) return CmdResult.notFound;
  final p = w.players[owner];
  if (p.stock[from] < amount) return CmdResult.cannotAfford;
  final got = amount * (100 - w.balance.marketFeePercent) ~/ 100;
  if (got < 1) return CmdResult.invalid;
  p.stock[from] -= amount;
  p.stock[to] += got;
  return CmdResult.ok;
}
