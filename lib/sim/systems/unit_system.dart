import 'dart:math' as math;

import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/pathfinding/astar.dart';
import 'package:age_of_empire_camer/sim/pathfinding/flow_field.dart';
import 'package:age_of_empire_camer/sim/systems/combat.dart';
import 'package:age_of_empire_camer/sim/systems/construction.dart';
import 'package:age_of_empire_camer/sim/systems/economy.dart';
import 'package:age_of_empire_camer/sim/systems/production.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Portée d'interaction (virgule fixe) : récolte, construction, dépôt.
const int interactReachFx = 288;

enum Approach { arrived, moving, waiting, failed }

// ───────────────────────── Ordres ─────────────────────────

/// Donne un ordre ; [queue] l'ajoute à la file au lieu de remplacer.
void issueOrder(
  World w,
  Unit u,
  Order o, {
  required bool queue,
  int flow = -1,
  int reach = 0,
  int cap = 0,
}) {
  if (!u.alive || u.state == UnitState.garrisoned) return;
  if (queue && u.orders.isNotEmpty) {
    if (u.orders.length < 32) u.orders.add(o);
    return;
  }
  u.leashed = false;
  u.orders
    ..clear()
    ..add(o);
  beginOrder(w, u, flow: flow, reach: reach, cap: cap);
}

/// Déplacement de groupe : flow field à partir de `flowFieldGroupMin` unités,
/// vitesse alignée sur la plus lente, arrivée en cercle autour de la cible.
void issueGroupMove(
  World w,
  List<Unit> us,
  int tx,
  int ty, {
  required bool queue,
}) {
  final movers = <Unit>[
    for (final u in us)
      if (u.state != UnitState.garrisoned) u,
  ];
  final n = movers.length;
  if (n == 0) return;
  final reach = n <= 1 ? 0 : (Fx.isqrt(n) + 1) ~/ 2;
  var cap = 0;
  if (n > 1) {
    cap = movers.map((u) => u.def.speedFxPerTick).reduce(math.min);
  }
  var flow = -1;
  if (!queue && n >= w.balance.flowFieldGroupMin) {
    flow = w.nextFlowId++;
    w.flows[flow] = FlowField(flow, GoalRect.tile(tx, ty, reach: reach));
  }
  for (final u in movers) {
    issueOrder(
      w,
      u,
      Order.move(tx, ty),
      queue: queue,
      flow: flow,
      reach: reach,
      cap: cap,
    );
  }
}

void stopUnit(World w, Unit u) {
  u.orders.clear();
  u.clearPath();
  u.targetId = -1;
  u.phase = Phase.approach;
  u.speedCap = 0;
  w.setState(u, UnitState.idle);
}

/// Démarre l'ordre en tête de file (ou passe en inactif).
void beginOrder(World w, Unit u, {int flow = -1, int reach = 0, int cap = 0}) {
  u.clearPath();
  u.targetId = -1;
  u.phase = Phase.approach;
  u.speedCap = cap;
  u.moveReach = reach;
  u.stuckTicks = 0;
  final o = u.order;
  if (o == null) {
    w.setState(u, UnitState.idle);
    return;
  }
  switch (o.kind) {
    case OrderKind.move:
      w.setState(u, UnitState.moving);
      if (flow >= 0) {
        u.flowId = flow;
      } else {
        w.paths.request(u);
      }
    case OrderKind.gather:
      final src = sourceOf(w, u.owner, o.a);
      if (src == null || !u.def.villager) {
        completeOrder(w, u);
        return;
      }
      if (u.carryRes >= 0 && u.carryRes != src.res.index) {
        u.carryRes = -1;
        u.carryAmt = 0;
      }
      u.targetId = o.a;
      u.lastTargetId = o.a;
      u.lastTargetX = src.rect[0];
      u.lastTargetY = src.rect[1];
      u.gatherRes = src.res.index;
      u.gatherProgress = 0;
      w.setState(u, UnitState.gathering);
      if (u.carryAmt >= w.players[u.owner].carryCapacity(u.def)) {
        u.phase = Phase.returning;
      }
    case OrderKind.build:
    case OrderKind.repair:
      final b = w.buildings[o.a];
      if (b == null || b.owner != u.owner || !u.def.villager) {
        completeOrder(w, u);
        return;
      }
      u.targetId = o.a;
      u.gatherProgress = 0;
      w.setState(u, UnitState.building);
    case OrderKind.attack:
      if (!isEnemyTarget(w, u.owner, o.a)) {
        completeOrder(w, u);
        return;
      }
      u.targetId = o.a;
      w.setState(u, UnitState.attacking);
    case OrderKind.garrison:
      final b = w.buildings[o.a];
      if (b == null || b.owner != u.owner || b.def.garrison == 0) {
        completeOrder(w, u);
        return;
      }
      u.targetId = o.a;
      w.setState(u, UnitState.moving);
      w.paths.request(u);
    case OrderKind.deposit:
      if (u.carryAmt <= 0 || !u.def.villager) {
        completeOrder(w, u);
        return;
      }
      w.setState(u, UnitState.gathering);
      u.phase = Phase.returning;
  }
}

/// Termine l'ordre courant et enchaîne sur le suivant.
void completeOrder(World w, Unit u) {
  if (u.orders.isNotEmpty) u.orders.removeAt(0);
  beginOrder(w, u);
}

// ───────────────────────── Références ─────────────────────────

/// Retire/redirige les références vers des entités supprimées (invariant 5).
void purgeReferences(World w, Unit u, Set<int> removed) {
  if (!u.alive) return;
  var headChanged = false;
  for (var i = 0; i < u.orders.length;) {
    final o = u.orders[i];
    if (o.hasTargetId && removed.contains(o.a)) {
      if (o.kind == OrderKind.gather && u.def.villager) {
        final next = findNextSource(w, u, u.gatherRes);
        if (next < 0 && u.carryAmt > 0) {
          // Plus de source : vide d'abord la charge portée.
          u.orders[i] = const Order(OrderKind.deposit, -1);
          if (i == 0) headChanged = true;
          i++;
          continue;
        }
        if (next >= 0) {
          u.orders[i] = Order.gather(next);
          if (i == 0) {
            u.targetId = next;
            u.lastTargetId = next;
            final r = w.rectOf(next);
            if (r != null) {
              u.lastTargetX = r[0];
              u.lastTargetY = r[1];
            }
            u.clearPath();
            if (u.phase != Phase.returning) u.phase = Phase.approach;
          }
          i++;
          continue;
        }
      }
      u.orders.removeAt(i);
      if (i == 0) headChanged = true;
      continue;
    }
    i++;
  }
  if (removed.contains(u.dropOffId)) {
    u.dropOffId = -1;
    if (u.phase == Phase.returning) u.clearPath();
  }
  if (removed.contains(u.followId)) u.followId = -1;
  if (removed.contains(u.garrisonIn)) u.garrisonIn = -1;
  if (removed.contains(u.lastTargetId)) u.lastTargetId = -1;
  if (removed.contains(u.targetId)) u.targetId = -1;
  if (headChanged) beginOrder(w, u);
}

// ───────────────────────── Mise à jour d'une unité ─────────────────────────

void updateUnit(World w, Unit u) {
  u.px = u.x;
  u.py = u.y;
  u.traveling = false;
  if (u.hp <= 0) {
    w.killUnit(u);
    return;
  }
  if (u.cooldown > 0) u.cooldown--;
  for (var i = 0; i < u.powerCd.length; i++) {
    if (u.powerCd[i] > 0) u.powerCd[i]--;
  }
  if (u.effects.isNotEmpty && !tickEffects(w, u)) return;
  if (isStunned(u)) return;

  switch (u.state) {
    case UnitState.idle:
      _updateIdle(w, u);
    case UnitState.moving:
      final o = u.order;
      if (o == null) {
        stopUnit(w, u);
      } else if (o.kind == OrderKind.garrison) {
        _updateGarrison(w, u, o);
      } else {
        _updateMove(w, u, o);
      }
    case UnitState.gathering:
      _updateGather(w, u);
    case UnitState.building:
      _updateBuild(w, u);
    case UnitState.attacking:
      _updateAttack(w, u);
    case UnitState.garrisoned:
    case UnitState.dead:
      return;
  }
  if (!u.alive || u.state == UnitState.garrisoned) return;

  // Filet de sécurité (invariant 7) : un déplacement a toujours un chemin,
  // une demande en cours ou un flow field.
  if (u.state == UnitState.moving &&
      !(u.pathPending || u.flowId >= 0 || u.pathIdx < u.path.length)) {
    w.paths.request(u);
  }

  _separate(w, u);
  if (u.traveling) {
    final moved = Fx.isqrt(
      (u.x - u.px) * (u.x - u.px) + (u.y - u.py) * (u.y - u.py),
    );
    final speed = _speedOf(w, u);
    if (moved * 4 < speed) {
      u.stuckTicks++;
      _handleStuck(w, u);
    } else {
      u.stuckTicks = 0;
    }
  }
}

int _speedOf(World w, Unit u) {
  var s = u.def.speedFxPerTick;
  final idx = w.map.index(
    u.tileX.clamp(0, w.map.width - 1),
    u.tileY.clamp(0, w.map.height - 1),
  );
  s = s * w.map.speedPercent(idx) ~/ 100;
  s = s * speedPercentOf(w, u) ~/ 100;
  if (u.speedCap > 0 && s > u.speedCap) s = u.speedCap;
  return s < 1 ? 1 : s;
}

void _handleStuck(World w, Unit u) {
  final b = w.balance;
  if (u.stuckTicks == b.stuckReplanTicks) {
    // Replanification complète depuis la case actuelle.
    final s = u.stuckTicks;
    u.clearPath();
    u.stuckTicks = s;
    w.paths.request(u);
  } else if (u.stuckTicks >= b.stuckTeleportTicks) {
    _teleportAhead(w, u);
    u.stuckTicks = 0;
  }
}

/// Dernier recours : saute à la prochaine case libre le long du chemin, ou à
/// la case libre la plus proche. Jamais de blocage éternel.
void _teleportAhead(World w, Unit u) {
  var tx = u.tileX;
  var ty = u.tileY;
  if (u.pathIdx + 1 < u.path.length) {
    final ti = u.path[u.pathIdx + 1];
    tx = ti % w.map.width;
    ty = ti ~/ w.map.width;
  }
  final free = nearestFreeTile(w, tx, ty, 6);
  if (free != null) {
    u.x = Fx.tileCenter(free.x);
    u.y = Fx.tileCenter(free.y);
  }
  u.clearPath();
  w.paths.request(u);
  w.violations.add(
    'Téléportation de secours (unité ${u.id}, tick ${w.tick}, '
    '${u.state.name}/${u.phase.name} ordre=${u.order} '
    'pos=(${u.tileX},${u.tileY}) chemin=${u.path.length - u.pathIdx} '
    'flow=${u.flowId} partiel=${u.pathPartial})',
  );
}

// ───────────────────────── Déplacement ─────────────────────────

int _advancePath(World w, Unit u, int speed) {
  var budget = speed;
  final width = w.map.width;
  while (budget > 0 && u.pathIdx < u.path.length) {
    final ti = u.path[u.pathIdx];
    final wx = Fx.tileCenter(ti % width);
    final wy = Fx.tileCenter(ti ~/ width);
    final dx = wx - u.x;
    final dy = wy - u.y;
    final d2 = dx * dx + dy * dy;
    if (d2 == 0) {
      u.pathIdx++;
      continue;
    }
    final dist = Fx.isqrt(d2);
    if (dist <= budget) {
      u.x = wx;
      u.y = wy;
      budget -= dist;
      u.pathIdx++;
    } else {
      final moved = _tryMove(
        w,
        u,
        u.x + dx * budget ~/ dist,
        u.y + dy * budget ~/ dist,
      );
      if (!moved) return speed - budget;
      budget = 0;
    }
  }
  return speed - budget;
}

/// Déplace l'unité vers (nx, ny) sans entrer dans une case bloquée : le long
/// d'un obstacle elle glisse sur un seul axe. Une unité déjà posée sur une case
/// bloquée peut en sortir librement.
bool _tryMove(World w, Unit u, int nx, int ny) {
  final m = w.map;
  bool free(int x, int y) {
    final tx = Fx.toInt(x);
    final ty = Fx.toInt(y);
    return m.inBounds(tx, ty) && !m.blocked(m.index(tx, ty));
  }

  if (free(nx, ny) || !free(u.x, u.y)) {
    u.x = nx;
    u.y = ny;
    return true;
  }
  if (free(nx, u.y)) {
    u.x = nx;
    return true;
  }
  if (free(u.x, ny)) {
    u.y = ny;
    return true;
  }
  return false;
}

void _validatePath(World w, Unit u) {
  if (u.pathVersion == w.map.version || u.pathIdx >= u.path.length) return;
  for (var i = u.pathIdx; i < u.path.length; i++) {
    if (w.map.blocked(u.path[i])) {
      u.clearPath();
      return;
    }
  }
  u.pathVersion = w.map.version;
}

/// Avance selon le chemin courant ou le flow field ; demande un chemin si besoin.
Approach _travel(World w, Unit u) {
  if (isRooted(u)) return Approach.waiting;
  final speed = _speedOf(w, u);
  if (u.flowId >= 0) {
    final flow = w.flows[u.flowId];
    if (flow == null) {
      u.flowId = -1;
    } else {
      var budget = speed;
      var steps = 0;
      u.traveling = true;
      while (budget > 0 && steps++ < 3) {
        final idx = w.map.index(
          u.tileX.clamp(0, w.map.width - 1),
          u.tileY.clamp(0, w.map.height - 1),
        );
        final nxt = flow.next(w.map, idx);
        if (nxt < 0) {
          // Pas de gradient (zone isolée) : repli sur A*.
          u.flowId = -1;
          u.traveling = false;
          w.paths.request(u);
          return Approach.waiting;
        }
        u.path = <int>[nxt];
        u.pathIdx = 0;
        final used = _advancePath(w, u, budget);
        budget -= used;
        if (used == 0) break;
      }
      u.path = <int>[];
      u.pathIdx = 0;
      return Approach.moving;
    }
  }
  _validatePath(w, u);
  if (u.pathPending) return Approach.waiting;
  if (u.pathIdx < u.path.length) {
    u.traveling = true;
    _advancePath(w, u, speed);
    if (u.pathIdx < u.path.length) return Approach.moving;
    // Fin de chemin atteinte pendant ce tick.
    return u.pathPartial ? Approach.failed : Approach.arrived;
  }
  if (u.pathVersion >= 0) {
    return u.pathPartial ? Approach.failed : Approach.arrived;
  }
  w.paths.request(u);
  return Approach.waiting;
}

/// Approche d'un rectangle cible jusqu'à [reachFx] (virgule fixe).
Approach _approach(World w, Unit u, List<int> rect, int reachFx) {
  if (World.distToRect(u.x, u.y, rect[0], rect[1], rect[2], rect[3]) <=
      reachFx) {
    u.clearPath();
    return Approach.arrived;
  }
  final r = _travel(w, u);
  if (r == Approach.arrived) {
    if (World.distToRect(u.x, u.y, rect[0], rect[1], rect[2], rect[3]) <=
        reachFx) {
      u.clearPath();
      return Approach.arrived;
    }
    // Chemin terminé mais hors de portée géométrique (cible déplacée…).
    final s = u.stuckTicks + 10;
    u.clearPath();
    u.stuckTicks = s;
    if (s >= w.balance.stuckTeleportTicks) {
      u.stuckTicks = 0;
      return Approach.failed;
    }
    w.paths.request(u);
    return Approach.waiting;
  }
  return r;
}

// ───────────────────────── Séparation ─────────────────────────

void _separate(World w, Unit u) {
  final radius = w.balance.separationRadius;
  if (radius <= 0) return;
  final map = w.map;
  final sp = w.spatial;
  final cx = u.tileX;
  final cy = u.tileY;
  var pushX = 0;
  var pushY = 0;
  for (var ty = cy - 1; ty <= cy + 1; ty++) {
    if (ty < 0 || ty >= map.height) continue;
    for (var tx = cx - 1; tx <= cx + 1; tx++) {
      if (tx < 0 || tx >= map.width) continue;
      final c = ty * map.width + tx;
      for (var k = sp.start[c]; k < sp.start[c + 1]; k++) {
        final oid = sp.items[k];
        if (oid == u.id) continue;
        final o = w.units[oid];
        if (o == null || !o.alive || o.state == UnitState.garrisoned) continue;
        var dx = u.x - o.x;
        var dy = u.y - o.y;
        var d2 = dx * dx + dy * dy;
        if (d2 >= radius * radius) continue;
        if (d2 == 0) {
          // Superposition exacte : écart déterministe selon les ids.
          dx = u.id > oid ? 1 : -1;
          dy = (u.id + oid).isEven ? 1 : -1;
          d2 = 2;
        }
        final d = Fx.isqrt(d2);
        final f = radius - d;
        pushX += dx * f ~/ d;
        pushY += dy * f ~/ d;
      }
    }
  }
  if (pushX == 0 && pushY == 0) return;
  // Les unités qui marchent cèdent peu ; les immobiles se laissent écarter.
  final div = u.traveling ? 6 : 3;
  // Une unité qui marche ne peut jamais être repoussée de plus d'un quart de sa
  // vitesse : la pression de foule ne doit pas annuler son déplacement.
  final maxPush = u.traveling ? math.max(1, _speedOf(w, u) ~/ 4) : 12;
  var sx = (pushX ~/ div).clamp(-maxPush, maxPush);
  var sy = (pushY ~/ div).clamp(-maxPush, maxPush);
  if (sx == 0 && sy == 0) {
    sx = pushX.sign;
    sy = pushY.sign;
  }
  final nx = u.x + sx;
  final ny = u.y + sy;
  final ntx = Fx.toInt(nx);
  final nty = Fx.toInt(ny);
  if (!map.inBounds(ntx, nty)) return;
  if (ntx != cx || nty != cy) {
    if (map.blocked(map.index(ntx, nty))) return;
    // Pas de passage en diagonale entre deux obstacles.
    if (ntx != cx && nty != cy) {
      if (map.blockedXY(ntx, cy) || map.blockedXY(cx, nty)) return;
    }
  }
  u.x = nx;
  u.y = ny;
}

/// Case libre la plus proche de (tx, ty), jusqu'au [maxRadius] (anneaux).
({int x, int y})? nearestFreeTile(World w, int tx, int ty, int maxRadius) {
  final m = w.map;
  for (var r = 0; r <= maxRadius; r++) {
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        if (math.max(dx.abs(), dy.abs()) != r) continue;
        final x = tx + dx;
        final y = ty + dy;
        if (m.inBounds(x, y) && !m.blocked(m.index(x, y))) {
          return (x: x, y: y);
        }
      }
    }
  }
  return null;
}

// ───────────────────────── Comportements ─────────────────────────

void _updateIdle(World w, Unit u) {
  if (!u.def.military) return;
  switch (u.stance) {
    case Stance.passive:
      return;
    case Stance.follow:
      final t = w.units[u.followId];
      if (t == null || !t.alive) return;
      final d = World.distToRect(u.x, u.y, t.tileX, t.tileY, 1, 1);
      if (d > 3 * Fx.one) {
        issueOrder(w, u, Order.move(t.tileX, t.tileY), queue: false);
        u.moveReach = 1;
      }
    case Stance.aggressive:
    case Stance.defensive:
      if ((w.tick + u.id) % w.balance.combat.acquirePeriod != 0) return;
      final radius = u.stance == Stance.aggressive
          ? u.def.vision
          : math.max(2, u.def.range) + 1;
      final t = _findEnemy(w, u, radius);
      if (t >= 0) {
        final hx = u.tileX;
        final hy = u.tileY;
        issueOrder(w, u, Order.attack(t), queue: false);
        u
          ..homeX = hx
          ..homeY = hy
          ..leashed = true;
      }
  }
}

int _findEnemy(World w, Unit u, int radius) {
  final map = w.map;
  final sp = w.spatial;
  final cx = u.tileX;
  final cy = u.tileY;
  var best = -1;
  var bestD = 1 << 60;
  for (
    var ty = math.max(0, cy - radius);
    ty <= math.min(map.height - 1, cy + radius);
    ty++
  ) {
    for (
      var tx = math.max(0, cx - radius);
      tx <= math.min(map.width - 1, cx + radius);
      tx++
    ) {
      final c = ty * map.width + tx;
      for (var k = sp.start[c]; k < sp.start[c + 1]; k++) {
        final o = w.units[sp.items[k]];
        if (o == null ||
            !o.alive ||
            !hostile(w, u.owner, o.owner) ||
            o.state == UnitState.garrisoned) {
          continue;
        }
        final dx = o.x - u.x;
        final dy = o.y - u.y;
        // Les combattants priment sur les civils à portée comparable.
        final d =
            dx * dx + dy * dy + (o.def.military ? 0 : 9 * Fx.one * Fx.one);
        if (d < bestD || (d == bestD && o.id < best)) {
          bestD = d;
          best = o.id;
        }
      }
    }
  }
  if (best >= 0) return best;
  for (final b in w.buildings.values) {
    if (!hostile(w, u.owner, b.owner) || b.def.isWall) continue;
    final d = World.distToRect(u.x, u.y, b.tx, b.ty, b.def.width, b.def.height);
    if (d <= radius * Fx.one && d < bestD) {
      bestD = d;
      best = b.id;
    }
  }
  return best;
}

void _updateMove(World w, Unit u, Order o) {
  if (u.flowId >= 0) {
    final flow = w.flows[u.flowId];
    if (flow != null && flow.goal.contains(u.tileX, u.tileY)) {
      completeOrder(w, u);
      return;
    }
  }
  final r = _travel(w, u);
  switch (r) {
    case Approach.arrived:
    case Approach.failed:
      completeOrder(w, u);
    case Approach.moving:
    case Approach.waiting:
      break;
  }
}

void _updateGarrison(World w, Unit u, Order o) {
  final b = w.buildings[o.a];
  if (b == null || b.owner != u.owner || !b.complete) {
    completeOrder(w, u);
    return;
  }
  final r = _approach(
    w,
    u,
    <int>[b.tx, b.ty, b.def.width, b.def.height],
    interactReachFx,
  );
  switch (r) {
    case Approach.arrived:
      if (b.garrisoned.length < b.def.garrison) {
        b.garrisoned.add(u.id);
        u.garrisonIn = b.id;
        u.orders.clear();
        u.clearPath();
        w.setState(u, UnitState.garrisoned);
      } else {
        completeOrder(w, u);
      }
    case Approach.failed:
      completeOrder(w, u);
    case Approach.moving:
    case Approach.waiting:
      break;
  }
}

/// Sort une unité d'un bâtiment, sur la case libre la plus proche.
void ejectUnit(World w, Unit u, Building b) {
  b.garrisoned.remove(u.id);
  u.garrisonIn = -1;
  if (u.state != UnitState.garrisoned) return;
  final spot = freeSpawnTile(w, b, -1, -1);
  if (spot != null) {
    u.x = Fx.tileCenter(spot.x);
    u.y = Fx.tileCenter(spot.y);
  }
  u.px = u.x;
  u.py = u.y;
  u.state = UnitState.idle; // transition garrisoned → idle autorisée
  u.orders.clear();
  u.clearPath();
}

// ── Récolte ──

void _updateGather(World w, Unit u) {
  final p = w.players[u.owner];
  final o = u.order;
  if (o == null ||
      (o.kind != OrderKind.gather && o.kind != OrderKind.deposit)) {
    stopUnit(w, u);
    return;
  }
  switch (u.phase) {
    case Phase.approach:
      if (o.kind == OrderKind.deposit) {
        u.phase = Phase.returning;
        return;
      }
      final src = sourceOf(w, u.owner, u.targetId);
      if (src == null) {
        _retarget(w, u);
        return;
      }
      final r = _approach(w, u, src.rect, interactReachFx);
      if (r == Approach.arrived) {
        u.phase = Phase.work;
        u.gatherProgress = 0;
      } else if (r == Approach.failed) {
        _abandonGather(w, u);
      }
    case Phase.work:
      final src = sourceOf(w, u.owner, u.targetId);
      if (src == null) {
        _retarget(w, u);
        return;
      }
      if (World.distToRect(
            u.x,
            u.y,
            src.rect[0],
            src.rect[1],
            src.rect[2],
            src.rect[3],
          ) >
          interactReachFx) {
        u.phase = Phase.approach;
        u.clearPath();
        return;
      }
      if (src.amount <= 0) {
        _onSourceEmpty(w, u, src);
        return;
      }
      final cap = p.carryCapacity(u.def);
      u.gatherProgress +=
          p.gatherPerTick(u.def, src.res) *
          (100 + gatherEffectPercent(u)) ~/
          100;
      var left = src.amount;
      while (u.gatherProgress >= 1000 && u.carryAmt < cap && left > 0) {
        u.gatherProgress -= 1000;
        u.carryRes = src.res.index;
        u.carryAmt++;
        left = takeFromSource(w, u.targetId);
      }
      if (u.carryAmt >= cap) {
        u.phase = Phase.returning;
        u.gatherProgress = 0;
        u.clearPath();
      } else if (left <= 0) {
        u.gatherProgress = 0;
      }
    case Phase.returning:
      _updateReturn(w, u);
  }
}

void _updateReturn(World w, Unit u) {
  final res = u.carryType;
  if (res == null || u.carryAmt <= 0) {
    u.phase = Phase.approach;
    u.clearPath();
    return;
  }
  var drop = w.buildings[u.dropOffId];
  if (drop == null || !drop.complete || !drop.def.dropOff.contains(res)) {
    drop = nearestDropOff(w, u, res);
    u.dropOffId = drop?.id ?? -1;
    u.clearPath();
  }
  if (drop == null) {
    // Aucun dépôt : l'unité reste inactive avec sa charge (icône d'alerte).
    u.orders.clear();
    u.targetId = -1;
    u.phase = Phase.approach;
    u.clearPath();
    w.setState(u, UnitState.idle);
    return;
  }
  final r = _approach(
    w,
    u,
    <int>[drop.tx, drop.ty, drop.def.width, drop.def.height],
    interactReachFx,
  );
  if (r == Approach.arrived) {
    w.players[u.owner].stock[res] += u.carryAmt;
    w.players[u.owner].stats.gathered[res.index] += u.carryAmt;
    u.carryAmt = 0;
    u.carryRes = -1;
    u.phase = Phase.approach;
    u.clearPath();
    if (u.order?.kind == OrderKind.deposit) {
      completeOrder(w, u);
    } else if (sourceOf(w, u.owner, u.targetId) == null) {
      _retarget(w, u);
    }
  } else if (r == Approach.failed) {
    u.dropOffId = -1;
    // Dépôt inaccessible : tente un autre dépôt une fois, sinon inactif.
    final other = nearestDropOff(w, u, res, exclude: drop.id);
    if (other == null) {
      u.orders.clear();
      u.targetId = -1;
      w.setState(u, UnitState.idle);
    } else {
      u.dropOffId = other.id;
      u.clearPath();
    }
  }
}

void _onSourceEmpty(World w, Unit u, Source src) {
  final b = w.buildings[u.targetId];
  if (b != null && b.isField) {
    if (reseedField(w, b)) return;
  }
  if (u.carryAmt > 0) {
    // Vide la charge d'abord, puis cherche une autre source.
    u.phase = Phase.returning;
    u.clearPath();
    return;
  }
  _retarget(w, u);
}

/// La source ciblée n'existe plus / est épuisée : en cherche une autre.
void _retarget(World w, Unit u) {
  if (u.carryAmt > 0) {
    u.phase = Phase.returning;
    u.clearPath();
    return;
  }
  final next = findNextSource(w, u, u.gatherRes);
  if (next >= 0) {
    u.orders[0] = Order.gather(next);
    final r = w.rectOf(next)!;
    u.targetId = next;
    u.lastTargetId = next;
    u.lastTargetX = r[0];
    u.lastTargetY = r[1];
    u.phase = Phase.approach;
    u.clearPath();
  } else {
    _abandonGather(w, u);
  }
}

void _abandonGather(World w, Unit u) {
  u.orders.clear();
  u.targetId = -1;
  u.phase = Phase.approach;
  u.clearPath();
  w.setState(u, UnitState.idle);
}

// ── Construction et réparation ──

void _updateBuild(World w, Unit u) {
  final o = u.order;
  final b = o == null ? null : w.buildings[o.a];
  if (o == null || b == null || b.owner != u.owner) {
    completeOrderAfterBuild(w, u, null);
    return;
  }
  final isRepair = o.kind == OrderKind.repair;
  if (!isRepair && b.complete) {
    completeOrderAfterBuild(w, u, b);
    return;
  }
  if (isRepair && b.hp >= b.maxHp) {
    completeOrder(w, u);
    return;
  }
  final rect = <int>[b.tx, b.ty, b.def.width, b.def.height];
  if (u.phase == Phase.approach) {
    final r = _approach(w, u, rect, interactReachFx);
    if (r == Approach.arrived) {
      u.phase = Phase.work;
    } else if (r == Approach.failed) {
      completeOrder(w, u);
    }
    return;
  }
  if (World.distToRect(u.x, u.y, b.tx, b.ty, b.def.width, b.def.height) >
      interactReachFx) {
    u.phase = Phase.approach;
    u.clearPath();
    return;
  }
  if (isRepair) {
    if (!repairStep(w, u, b)) completeOrder(w, u);
  } else {
    b.buildersThisTick++;
  }
}

void completeOrderAfterBuild(World w, Unit u, Building? b) {
  final hadMore = u.orders.length > 1;
  if (u.orders.isNotEmpty) u.orders.removeAt(0);
  if (hadMore || b == null) {
    beginOrder(w, u);
    return;
  }
  final follow = autoWorkAfterBuild(w, u, b);
  if (follow != null) {
    u.orders.add(follow);
  }
  beginOrder(w, u);
}

// ── Combat ──

int _attackReachFx(World w, Unit u, int tx, int ty) {
  if (u.def.range == 0) return interactReachFx;
  var tiles = rangeTilesOf(w, u);
  if (higherGround(w, u.tileX, u.tileY, tx, ty)) tiles++;
  return tiles * Fx.one + 64;
}

/// Abandon d'une poursuite lancée automatiquement quand la cible entraîne
/// l'unité trop loin de son point de départ.
bool _leashBroken(World w, Unit u) {
  if (!u.leashed) return false;
  final lim = w.balance.combat.leashTiles;
  return (u.tileX - u.homeX).abs() > lim || (u.tileY - u.homeY).abs() > lim;
}

void _updateAttack(World w, Unit u) {
  final o = u.order;
  if (o == null || o.kind != OrderKind.attack) {
    stopUnit(w, u);
    return;
  }
  final tu = w.units[o.a];
  final tb = w.buildings[o.a];
  final unitOk =
      tu != null &&
      tu.alive &&
      hostile(w, u.owner, tu.owner) &&
      tu.state != UnitState.garrisoned;
  final buildingOk = tb != null && hostile(w, u.owner, tb.owner);
  if (!unitOk && !buildingOk) {
    completeOrder(w, u);
    return;
  }
  if (_leashBroken(w, u)) {
    final hx = u.homeX;
    final hy = u.homeY;
    issueOrder(w, u, Order.move(hx, hy), queue: false);
    return;
  }
  final rect = unitOk
      ? <int>[tu.tileX, tu.tileY, 1, 1]
      : <int>[tb!.tx, tb.ty, tb.def.width, tb.def.height];
  final reachFx = _attackReachFx(w, u, rect[0], rect[1]);
  final dist = World.distToRect(u.x, u.y, rect[0], rect[1], rect[2], rect[3]);
  if (dist > reachFx) {
    // Cible mobile : recalcul périodique du chemin quand elle s'est éloignée.
    if (unitOk && u.path.isNotEmpty && (w.tick + u.id) % 10 == 0) {
      final end = u.path.last;
      if ((end % w.map.width - rect[0]).abs() > 2 ||
          (end ~/ w.map.width - rect[1]).abs() > 2) {
        u.clearPath();
      }
    }
    final r = _approach(w, u, rect, reachFx);
    if (r == Approach.failed) {
      // Cible inaccessible (mur, enclave) : abandon, sauf bâtiment à frapper
      // depuis une case adjacente.
      completeOrder(w, u);
    }
    return;
  }
  u.clearPath();
  if (u.cooldown > 0) return;
  u.cooldown = u.def.attackCooldownTicks;

  var pct = attackPercentOf(w, u);
  final tx = unitOk ? tu.tileX : tb!.tx;
  final ty = unitOk ? tu.tileY : tb!.ty;
  if (higherGround(w, u.tileX, u.tileY, tx, ty)) {
    pct += w.balance.combat.heightBonusPercent;
  }
  var first = false;
  for (var i = 0; i < u.effects.length; i++) {
    if (u.effects[i].kind == EffectKind.firstHitPct) {
      pct += u.effects[i].value;
      u.effects.removeAt(i);
      first = true;
      break;
    }
  }

  if (u.def.projectileSpeed > 0) {
    final aimX = unitOk ? tu.x : tb!.center.x;
    final aimY = unitOk ? tu.y : tb!.center.y;
    launchUnitProjectile(w, u, o.a, aimX, aimY, pct, firstHit: first);
    return;
  }
  if (unitOk) {
    final dmg = calcUnitDamage(w, u.def, pct, tu);
    final killed = damageUnit(w, tu, dmg, srcOwner: u.owner, src: u);
    if (!killed && u.def.onHit != null) {
      addEffect(w, tu, u.def.onHit!, -1, srcOwner: u.owner, srcUnit: u);
    }
  } else {
    damageBuilding(
      w,
      tb!,
      calcBuildingDamage(w, u.def, pct, tb),
      srcOwner: u.owner,
    );
  }
}

/// Rectangle d'une source de ressource pour les utilitaires de requête.
Source? sourceOfPublic(World w, int owner, int id) => sourceOf(w, owner, id);

/// Nombre d'unités déjà affectées à une source (limite de villageois par champ).
int gatherersOn(World w, int id, {int? except}) {
  var n = 0;
  for (final u in w.units.values) {
    if (u.targetId == id && u.state == UnitState.gathering && u.id != except) {
      n++;
    }
  }
  return n;
}

/// Utilitaire pour les tests/IA : ressource transportée.
Res? carriedType(Unit u) => u.carryType;
