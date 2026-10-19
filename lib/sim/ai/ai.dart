import 'dart:math' as math;
import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/combat.dart';
import 'package:age_of_empire_camer/sim/systems/construction.dart';
import 'package:age_of_empire_camer/sim/systems/economy.dart';
import 'package:age_of_empire_camer/sim/systems/production.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/player.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Indices de la mémoire d'IA ([Player.aiMem]).
abstract final class _Mem {
  static const int score = 0;
  static const int scoreTick = 1;
  static const int attackState = 2;
  static const int targetX = 3;
  static const int targetY = 4;
  static const int waves = 5;
  static const int watchdog = 6;
  static const int retreatUntil = 7;
}

/// États de la machine d'attaque.
abstract final class AiAttackState {
  static const int gathering = 0;
  static const int marching = 1;
  static const int retreating = 2;
}

/// Fait réfléchir chaque IA à son rythme (voir `ai.json`). L'IA n'utilise que
/// des commandes — exactement comme le joueur — et ne lit que son propre état
/// et ce que son brouillard de guerre lui montre (les positions de départ des
/// adversaires font exception : voir docs/DECISIONS.md).
void updateAi(World w) {
  if (!w.aiEnabled || w.gameOver) return;
  for (final p in w.players) {
    if (p.aiLevel < 0 || p.defeated) continue;
    final diff = w.defs.ai.difficulties[p.aiLevel];
    if ((w.tick + p.id * 7) % diff.thinkTicks != 0) continue;
    _Brain(w, p, diff).think();
  }
}

class _Brain {
  _Brain(this.w, this.p, this.diff)
    : id = p.id,
      pers = p.clan >= 0
          ? w.defs.clans[p.clan].personality
          : const AiPersonality(
              aggression: 50,
              economy: 50,
              towers: 30,
              siege: 30,
              cavalry: 30,
              raidWave: 14,
            ),
      budget = p.stock.copy();

  final World w;
  final Player p;
  final DifficultyDef diff;
  final AiPersonality pers;
  final int id;

  /// Ressources encore disponibles pour cette réflexion (les commandes ne
  /// sont exécutées qu'au tick suivant).
  final Stock budget;

  final Set<int> _claimed = <int>{};
  final List<Unit> _mine = <Unit>[];
  final List<Unit> _villagers = <Unit>[];
  final List<Unit> _army = <Unit>[];
  final Map<String, List<Building>> _done = <String, List<Building>>{};
  final Map<String, int> _under = <String, int>{};
  final List<Unit> _foes = <Unit>[];
  final List<Building> _foeBuildings = <Building>[];
  Building? _tc;
  int _homeX = 0;
  int _homeY = 0;
  bool _saving = false;
  Stock _reserve = Stock();

  AiDef get ai => w.defs.ai;

  // ───────────────────────── Réflexion ─────────────────────────

  void think() {
    _scan();
    _economy();
    _ageUp();
    _buildings();
    _research();
    _army2();
    _tactics();
    _watchdog();
  }

  void _scan() {
    final map = w.map;
    for (final u in w.units.values) {
      if (!u.alive) continue;
      if (u.owner == id) {
        _mine.add(u);
        if (u.state == UnitState.garrisoned) continue;
        if (u.def.villager) {
          _villagers.add(u);
        } else if (u.def.military) {
          _army.add(u);
        }
      } else if (hostile(w, id, u.owner) &&
          u.state != UnitState.garrisoned &&
          map.inBounds(u.tileX, u.tileY) &&
          p.visible[map.index(u.tileX, u.tileY)] == 1) {
        _foes.add(u);
      }
    }
    for (final b in w.buildings.values) {
      if (b.owner == id) {
        if (b.complete) {
          (_done[b.def.id] ??= <Building>[]).add(b);
        } else {
          _under[b.def.id] = (_under[b.def.id] ?? 0) + 1;
        }
      } else if (hostile(w, id, b.owner) &&
          p.explored[map.index(b.tx, b.ty)] == 1) {
        _foeBuildings.add(b);
      }
    }
    final tcs = _done.entries
        .where((e) => w.defs.building(e.key).townCenter)
        .expand((e) => e.value);
    _tc = tcs.isEmpty ? null : tcs.first;
    if (_tc != null) {
      _homeX = _tc!.tx + _tc!.def.width ~/ 2;
      _homeY = _tc!.ty + _tc!.def.height ~/ 2;
    } else {
      _homeX = p.startX;
      _homeY = p.startY;
    }
    _targetAge = math.min(diff.index + 1, w.defs.ages.length - 1);
  }

  late int _targetAge;

  /// Cases atteignables à pied depuis le centre-ville (calculé à la demande).
  Uint8List? _reach;

  Uint8List _reachable() {
    final cached = _reach;
    if (cached != null) return cached;
    final m = w.map;
    final seen = Uint8List(m.size);
    final queue = <int>[];
    void seed(int x, int y) {
      if (!m.inBounds(x, y)) return;
      final i = m.index(x, y);
      if (seen[i] == 1 || m.blocked(i)) return;
      seen[i] = 1;
      queue.add(i);
    }

    final tc = _tc;
    if (tc != null) {
      for (var y = tc.ty - 1; y <= tc.ty + tc.def.height; y++) {
        for (var x = tc.tx - 1; x <= tc.tx + tc.def.width; x++) {
          seed(x, y);
        }
      }
    } else {
      seed(_homeX, _homeY);
    }
    for (var head = 0; head < queue.length; head++) {
      final i = queue[head];
      final x = i % m.width;
      final y = i ~/ m.width;
      seed(x + 1, y);
      seed(x - 1, y);
      seed(x, y + 1);
      seed(x, y - 1);
    }
    return _reach = seen;
  }

  /// Une case voisine de la ressource est-elle accessible à pied ?
  bool _nodeReachable(ResourceNode n) {
    final seen = _reachable();
    final m = w.map;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final x = n.tx + dx;
        final y = n.ty + dy;
        if (m.inBounds(x, y) && seen[m.index(x, y)] == 1) return true;
      }
    }
    return false;
  }

  int _count(String defId) =>
      (_done[defId]?.length ?? 0) + (_under[defId] ?? 0);

  bool _has(String defId) => _done[defId]?.isNotEmpty ?? false;

  /// [essential] : dépense courante (villageois) qui peut puiser dans la
  /// réserve d'âge tant que l'économie est jeune ; [critical] : toujours
  /// permise (huttes, dépôts, centre-ville).
  bool _canSpend(Stock cost, {bool essential = false, bool critical = false}) {
    if (!budget.covers(cost)) return false;
    if (critical || !_saving) return true;
    if (essential && _villagers.length < 14) return true;
    for (final r in Res.values) {
      if (budget[r] - cost[r] < _reserve[r]) return false;
    }
    return true;
  }

  void _spend(Stock cost) => budget.subtract(cost);

  void _send(Command c) => w.submit(c);

  // ───────────────────────── Économie ─────────────────────────

  void _economy() {
    if (_tc == null) {
      _rebuildTownCenter();
    } else {
      _trainVillagers();
    }
    _houses();
    _finishConstructions();
    _assignIdle();
    _balanceWorkers();
    _cleanFields();
    _trade();
  }

  /// Échange le surplus contre ce qui manque (sources épuisées, filière
  /// absente). Le marché prélève des frais : on n'échange que l'excédent.
  void _trade() {
    final markets = _done['market'];
    if (markets == null || markets.isEmpty) return;
    Res? rich;
    var most = 0;
    for (final r in Res.values) {
      if (budget[r] > most) {
        most = budget[r];
        rich = r;
      }
    }
    if (rich == null || most < 1200) return;
    // Besoin : coût du prochain âge d'abord, sinon la ressource la plus basse.
    final need = Stock();
    if (p.age < _targetAge) need.add(w.defs.ages[p.age + 1].cost);
    Res? target;
    var worst = 1 << 30;
    for (final r in Res.values) {
      if (r == rich) continue;
      final shortage = budget[r] - (need[r] > 300 ? need[r] : 300);
      if (shortage < 0 && shortage < worst) {
        worst = shortage;
        target = r;
      }
    }
    if (target == null) return;
    final amount = math.min(most - 800, math.max(200, -worst * 2));
    if (amount < 100) return;
    budget[rich] -= amount;
    _send(ExchangeCmd(id, rich, target, amount));
  }

  /// Un chantier sans bâtisseur (ouvrier tué, ordre perdu) est repris par le
  /// villageois disponible le plus proche.
  void _finishConstructions() {
    var assigned = 0;
    for (final b in w.buildings.values) {
      if (b.owner != id || b.complete || assigned >= 3) continue;
      final hasBuilder = _villagers.any((u) {
        final o = u.order;
        return o != null &&
            (o.kind == OrderKind.build || o.kind == OrderKind.repair) &&
            o.a == b.id;
      });
      if (hasBuilder) continue;
      final builders = _pickBuilders(1, b.tx, b.ty);
      if (builders.isEmpty) continue;
      _claimed.add(builders.first.id);
      _send(RepairCmd(id, [builders.first.id], b.id));
      assigned++;
    }
  }

  /// Supprime les champs épuisés et sans cultivateur : ils encombrent la base.
  void _cleanFields() {
    var removed = 0;
    for (final b in w.buildings.values) {
      if (b.owner != id || !b.isField || !b.complete || b.stock > 0) continue;
      if (removed >= 2) return;
      if (_villagers.any((u) => u.targetId == b.id)) continue;
      _send(DeleteCmd(id, b.id));
      removed++;
    }
  }

  int get _villagerTarget {
    final base = 20 + pers.economy ~/ 4;
    return math.min(diff.maxVillagers, base + p.age * 8);
  }

  void _trainVillagers() {
    var queued = 0;
    for (final b in _done.values.expand((e) => e)) {
      for (final q in b.queue) {
        if (!q.isTech && !q.isAge && w.defs.units[q.defIndex].villager) {
          queued++;
        }
      }
    }
    final tcs = _done.entries
        .where((e) => w.defs.building(e.key).townCenter)
        .expand((e) => e.value);
    for (final tc in tcs) {
      if (_villagers.length + queued >= _villagerTarget) return;
      if (tc.queue.length >= 2) continue;
      if (p.popUsed + queued >= p.popCap) return;
      final v = w.defs.units.firstWhere((u) => u.villager);
      if (!_canSpend(v.cost, essential: true)) return;
      _spend(v.cost);
      _send(TrainCmd(id, tc.id, v.id));
      queued++;
    }
  }

  void _houses() {
    if (p.popCap >= w.balance.maxPopulation) return;
    var queuedPop = 0;
    for (final b in _done.values.expand((e) => e)) {
      queuedPop += b.queue.where((q) => !q.isTech && !q.isAge).length;
    }
    final room = p.popCap - p.popUsed - queuedPop;
    final building = (_under['hut'] ?? 0) > 0;
    if (room > ai.hutMargin || building) return;
    final hut = w.defs.building('hut');
    if (!_canSpend(hut.cost, critical: true)) return;
    _build(hut, 1, _homeX, _homeY, minR: 3);
  }

  void _rebuildTownCenter() {
    final tcDef = w.defs.buildings.firstWhere((b) => b.townCenter);
    if ((_under[tcDef.id] ?? 0) > 0) return;
    if (!_canSpend(tcDef.cost, critical: true)) return;
    _build(tcDef, 3, p.startX, p.startY, minR: 3, maxR: 18);
  }

  /// Pose un bâtiment avec [n] bâtisseurs proches. Renvoie vrai si lancé.
  bool _build(
    BuildingDef def,
    int n,
    int nearX,
    int nearY, {
    int minR = 2,
    int maxR = 16,
    bool gap = true,
  }) {
    final builders = _pickBuilders(n, nearX, nearY);
    if (builders.isEmpty) return false;
    for (var r = minR; r <= maxR; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx.abs() != r && dy.abs() != r) continue;
          final x = nearX + dx;
          final y = nearY + dy;
          if (validatePlacement(w, id, def, x, y) != CmdResult.ok) continue;
          if (gap && !_hasGap(def, x, y)) continue;
          if (!_keepsOpen(def, x, y)) continue;
          _spend(def.cost);
          _claimed.addAll(builders.map((u) => u.id));
          _send(BuildCmd(id, builders.map((u) => u.id).toList(), def.id, x, y));
          _under[def.id] = (_under[def.id] ?? 0) + 1;
          return true;
        }
      }
    }
    return false;
  }

  /// Nombre de cases atteignables à pied depuis le centre-ville, en comptant
  /// en plus l'emprise (ex, ey, ew, eh) comme bloquée.
  int _floodCount(int ex, int ey, int ew, int eh) {
    final tc = _tc;
    if (tc == null) return 1 << 30;
    final m = w.map;
    final seen = Uint8List(m.size);
    final queue = <int>[];
    bool blockedAt(int x, int y) =>
        (x >= ex && x < ex + ew && y >= ey && y < ey + eh) ||
        m.blocked(m.index(x, y));
    void seed(int x, int y) {
      if (!m.inBounds(x, y)) return;
      final i = m.index(x, y);
      if (seen[i] == 1 || blockedAt(x, y)) return;
      seen[i] = 1;
      queue.add(i);
    }

    for (var y = tc.ty - 1; y <= tc.ty + tc.def.height; y++) {
      for (var x = tc.tx - 1; x <= tc.tx + tc.def.width; x++) {
        seed(x, y);
      }
    }
    for (var head = 0; head < queue.length; head++) {
      final i = queue[head];
      final x = i % m.width;
      final y = i ~/ m.width;
      seed(x + 1, y);
      seed(x - 1, y);
      seed(x, y + 1);
      seed(x, y - 1);
    }
    return queue.length;
  }

  int? _openBase;

  /// Le bâtiment ne doit pas emmurer la base : après sa pose, la zone
  /// accessible depuis le centre-ville ne perd (presque) que son emprise.
  bool _keepsOpen(BuildingDef def, int x, int y) {
    if (def.isWall || _tc == null) return true;
    final base = _openBase ??= _floodCount(-1, -1, 0, 0);
    final after = _floodCount(x, y, def.width, def.height);
    return after >= base - def.width * def.height - 6;
  }

  /// Laisse une case libre autour du bâtiment pour que les unités circulent.
  bool _hasGap(BuildingDef def, int x, int y) {
    final m = w.map;
    for (var yy = y - 1; yy <= y + def.height; yy++) {
      for (var xx = x - 1; xx <= x + def.width; xx++) {
        final inside =
            xx >= x && yy >= y && xx < x + def.width && yy < y + def.height;
        if (inside || !m.inBounds(xx, yy)) continue;
        final occ = m.occupant[m.index(xx, yy)];
        if (occ == 0) continue;
        final b = w.buildings[occ];
        if (b != null && !b.isField && !b.def.isWall) return false;
      }
    }
    return true;
  }

  List<Unit> _pickBuilders(int n, int x, int y) {
    final cands = <Unit>[
      for (final u in _villagers)
        if (!_claimed.contains(u.id) &&
            (u.isIdle ||
                u.state == UnitState.gathering ||
                u.state == UnitState.moving))
          u,
    ];
    cands.sort((a, b) {
      final da = (a.tileX - x).abs() + (a.tileY - y).abs();
      final db = (b.tileX - x).abs() + (b.tileY - y).abs();
      return da != db ? da.compareTo(db) : a.id.compareTo(b.id);
    });
    return cands.take(n).toList();
  }

  /// Ressources classées de la plus à la moins nécessaire.
  List<Res> _byNeed(Map<Res, int> counts) {
    final scored = <(Res, int)>[];
    for (final r in Res.values) {
      final share = ai.shares[r]!;
      if (share == 0) continue;
      var score = counts[r]! * 1000 ~/ share;
      // Les ressources abondantes sont délaissées.
      if (budget[r] > 1500) score += 400;
      if (r == Res.wood && budget[r] < 150) score -= 300;
      if (r == Res.food && budget[r] < 100) score -= 200;
      scored.add((r, score));
    }
    scored.sort((a, b) {
      final c = a.$2.compareTo(b.$2);
      return c != 0 ? c : a.$1.index.compareTo(b.$1.index);
    });
    return <Res>[for (final e in scored) e.$1];
  }

  Map<Res, int> _gathererCounts() {
    final counts = <Res, int>{for (final r in Res.values) r: 0};
    for (final u in _villagers) {
      if (u.gatherRes >= 0 &&
          (u.state == UnitState.gathering || u.state == UnitState.moving)) {
        final r = Res.values[u.gatherRes];
        counts[r] = counts[r]! + 1;
      }
    }
    return counts;
  }

  void _assignIdle() {
    final counts = _gathererCounts();
    for (final u in _villagers) {
      if (!u.isIdle || _claimed.contains(u.id)) continue;
      final order = u.carryAmt > 0
          ? <Res>[u.carryType!, ..._byNeed(counts)]
          : _byNeed(counts);
      for (final res in order) {
        if (_sendToWork(u, res)) {
          counts[res] = counts[res]! + 1;
          _claimed.add(u.id);
          break;
        }
      }
    }
  }

  /// Effectif cible de chaque ressource : parts du fichier de données,
  /// corrigées par les stocks (on récolte ce qui manque).
  Map<Res, int> _targets() {
    final weights = <Res, int>{};
    var sum = 0;
    for (final r in Res.values) {
      var wgt = ai.shares[r]! * 100;
      final stock = budget[r];
      if (stock < 150) {
        wgt *= 2;
      } else if (stock > 2500) {
        wgt ~/= 8;
      } else if (stock > 1200) {
        wgt ~/= 3;
      } else if (stock > 700) {
        wgt = wgt * 2 ~/ 3;
      }
      weights[r] = wgt;
      sum += wgt;
    }
    final n = _villagers.length;
    return <Res, int>{
      for (final r in Res.values)
        r: sum == 0 ? 0 : (weights[r]! * n + sum ~/ 2) ~/ sum,
    };
  }

  /// Redirige un villageois par réflexion d'une filière surpeuplée vers une
  /// filière en manque (évite l'effondrement d'une ressource).
  void _balanceWorkers() {
    if (_villagers.length < 8) return;
    final counts = _gathererCounts();
    final target = _targets();
    Res? needy;
    var worst = 0;
    Res? rich;
    var surplus = 0;
    for (final r in Res.values) {
      final gap = target[r]! - counts[r]!;
      if (gap > worst) {
        worst = gap;
        needy = r;
      }
      if (-gap > surplus) {
        surplus = -gap;
        rich = r;
      }
    }
    if (needy == null || rich == null || worst < 2 || surplus < 2) return;
    for (final u in _villagers) {
      if (_claimed.contains(u.id) ||
          u.state != UnitState.gathering ||
          u.gatherRes != rich.index ||
          u.carryAmt > 0) {
        continue;
      }
      if (_sendToWork(u, needy)) {
        _claimed.add(u.id);
        return;
      }
    }
  }

  /// Envoie un villageois récolter [res] ; construit au besoin le dépôt ou le
  /// champ manquant. Renvoie vrai si une commande a été émise.
  bool _sendToWork(Unit u, Res res) {
    final ax = _homeX;
    final ay = _homeY;
    if (res == Res.food) {
      Building? field;
      var bestD = 1 << 60;
      for (final b in w.buildings.values) {
        if (b.owner != id || !b.isField || !b.complete || b.stock <= 0) {
          continue;
        }
        if (gatherersOnField(w, b.id, u.id) >= w.balance.fieldGatherers) {
          continue;
        }
        final d = (b.tx - ax) * (b.tx - ax) + (b.ty - ay) * (b.ty - ay);
        if (d < bestD) {
          bestD = d;
          field = b;
        }
      }
      final node = _nearestNode(Res.food, u, maxTiles: 14);
      if (node != null &&
          (field == null || _dist2(node.tx, node.ty, ax, ay) < bestD)) {
        if (_ensureDropOff(Res.food, node.tx, node.ty, u)) return true;
        _send(GatherCmd(id, [u.id], node.id));
        return true;
      }
      if (field != null) {
        _send(GatherCmd(id, [u.id], field.id));
        return true;
      }
      final fieldDef = w.defs.building('field');
      if (_canSpend(fieldDef.cost, critical: true)) {
        final near = _doneFoodDropOff();
        final ok = _buildWith(fieldDef, [u], near.$1, near.$2);
        if (ok) return true;
      }
      // Pas de champ possible : tant pis, un gibier plus lointain.
      final far = _nearestNode(Res.food, u);
      if (far == null) return false;
      if (_ensureDropOff(Res.food, far.tx, far.ty, u)) return true;
      _send(GatherCmd(id, [u.id], far.id));
      return true;
    }
    final node = _nearestNode(res, u);
    if (node == null) return false;
    if (_ensureDropOff(res, node.tx, node.ty, u)) return true;
    _send(GatherCmd(id, [u.id], node.id));
    return true;
  }

  (int, int) _doneFoodDropOff() {
    for (final e in _done.entries) {
      final d = w.defs.building(e.key);
      if (d.dropOff.contains(Res.food) && e.value.isNotEmpty) {
        final b = e.value.first;
        return (b.tx + d.width ~/ 2, b.ty + d.height ~/ 2);
      }
    }
    return (_homeX, _homeY);
  }

  bool _buildWith(
    BuildingDef def,
    List<Unit> builders,
    int nearX,
    int nearY, {
    int minR = 2,
    int maxR = 14,
  }) {
    for (var r = minR; r <= maxR; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx.abs() != r && dy.abs() != r) continue;
          final x = nearX + dx;
          final y = nearY + dy;
          if (validatePlacement(w, id, def, x, y) != CmdResult.ok) continue;
          if (!def.isField && !_hasGap(def, x, y)) continue;
          if (!_keepsOpen(def, x, y)) continue;
          _spend(def.cost);
          _send(BuildCmd(id, builders.map((u) => u.id).toList(), def.id, x, y));
          _under[def.id] = (_under[def.id] ?? 0) + 1;
          _claimed.addAll(builders.map((u) => u.id));
          return true;
        }
      }
    }
    return false;
  }

  int _dist2(int ax, int ay, int bx, int by) =>
      (ax - bx) * (ax - bx) + (ay - by) * (ay - by);

  ResourceNode? _nearestNode(Res res, Unit u, {int maxTiles = 45}) {
    final near = _nearestNodeIn(res, maxTiles, explored: true);
    if (near != null || maxTiles < 40) return near;
    // Plus rien de connu à proximité : on part à la recherche plus loin.
    return _nearestNodeIn(res, 96, explored: false);
  }

  ResourceNode? _nearestNodeIn(
    Res res,
    int maxTiles, {
    required bool explored,
  }) {
    ResourceNode? best;
    var bestD = 1 << 60;
    for (final n in w.nodes.values) {
      if (n.res != res || n.amount <= 0) continue;
      final d = _dist2(n.tx, n.ty, _homeX, _homeY);
      if (d > maxTiles * maxTiles) continue;
      // Pas de ressource sur une zone inconnue et lointaine.
      if (explored && p.explored[w.map.index(n.tx, n.ty)] == 0 && d > 28 * 28) {
        continue;
      }
      if (!_nodeReachable(n)) continue;
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
    return best;
  }

  /// Construit un dépôt près d'une source trop éloignée. Renvoie vrai si le
  /// bâtisseur a reçu l'ordre de le construire.
  bool _ensureDropOff(Res res, int sx, int sy, Unit u) {
    var near = false;
    for (final b in w.buildings.values) {
      if (b.owner != id || !b.def.dropOff.contains(res)) continue;
      final d = World.distToRect(
        Fx.tileCenter(sx),
        Fx.tileCenter(sy),
        b.tx,
        b.ty,
        b.def.width,
        b.def.height,
      );
      if (d <= 7 * Fx.one) {
        near = true;
        break;
      }
    }
    if (near) return false;
    final campId = res == Res.wood
        ? 'lumber_camp'
        : (res == Res.food ? 'granary' : 'mining_camp');
    final def = w.defs.building(campId);
    if ((_under[campId] ?? 0) > 0) return false;
    if (!_canSpend(def.cost, critical: true)) return false;
    return _buildWith(def, [u], sx, sy, minR: 1, maxR: 6);
  }

  // ───────────────────────── Âges ─────────────────────────

  void _ageUp() {
    _saving = false;
    _reserve = Stock();
    if (p.age >= _targetAge) return;
    final next = p.age + 1;
    final age = w.defs.ages[next];
    // Prérequis : on les construit.
    for (final req in age.requiresBuildings) {
      if (_has(req)) continue;
      final def = w.defs.building(req);
      if (def.age > p.age) continue;
      if (_villagers.length < 8) return;
      if ((_under[req] ?? 0) == 0 && _canSpend(def.cost, critical: true)) {
        final where = def.width * def.height > 12 ? 7 : 4;
        _build(def, 2, _homeX, _homeY, minR: where);
      }
      return;
    }
    if (_villagers.length < 12) return;
    _saving = true;
    _reserve = age.cost.copy();
    if (!_canSpend(age.cost, critical: true)) return;
    for (final e in _done.entries) {
      for (final b in e.value) {
        if (b.def.agesUp &&
            age.researchedAt.contains(b.def.id) &&
            b.queue.isEmpty) {
          _spend(age.cost);
          _send(AgeUpCmd(id, b.id));
          return;
        }
      }
    }
  }

  // ───────────────────────── Bâtiments ─────────────────────────

  void _buildings() {
    if (_tc == null || _villagers.length < 6) return;
    void want(String defId, int count, {int minVillagers = 0, int r = 5}) {
      final def = w.defs.building(defId);
      if (def.age > p.age) return;
      if (_count(defId) >= count) return;
      if ((_under[defId] ?? 0) > 0) return;
      if (_villagers.length < minVillagers) return;
      if (!_canSpend(def.cost)) return;
      final (ax, ay) = _anchorToward(def, r);
      _build(def, 2, ax, ay, minR: 1, maxR: 18);
    }

    if (p.age == 0) want('granary', 1, minVillagers: 8);
    want('barracks', 1, minVillagers: 10);
    if (p.age >= 1) {
      want('forge', 1, minVillagers: 14);
      want('barracks', 2, minVillagers: 24);
      want('palace', 1, minVillagers: 16);
    }
    if (p.age >= 1 && pers.towers >= 25 && _villagers.length >= 18) {
      want('tower', 1 + pers.towers ~/ 30, minVillagers: 18, r: 9);
    }
    if (p.age >= 2) {
      if (pers.cavalry >= 40) want('stable', 1, minVillagers: 20);
      if (pers.siege >= 50) want('siege_workshop', 1, minVillagers: 22);
      if (diff.useHero) want('altar', 1, minVillagers: 20);
      if (pers.towers >= 70) want('fortress', 1, minVillagers: 26, r: 8);
      if (pers.aggression >= 60) want('barracks', 3, minVillagers: 28);
    }
    if (p.age >= 1) {
      final surplus = Res.values.any((r) => budget[r] > 1200);
      if (_targetAge >= 3 || surplus) want('market', 1, minVillagers: 20);
    }
  }

  /// Point d'ancrage d'un bâtiment : légèrement vers le centre de la carte
  /// (côté ennemi) pour les bâtiments militaires et défensifs.
  (int, int) _anchorToward(BuildingDef def, int dist) {
    final military = def.trains.isNotEmpty || def.attack > 0;
    if (!military) return (_homeX, _homeY);
    final cx = w.map.width ~/ 2;
    final cy = w.map.height ~/ 2;
    final dx = cx - _homeX;
    final dy = cy - _homeY;
    final len = math.max(1, math.max(dx.abs(), dy.abs()));
    return (_homeX + dx * dist ~/ len, _homeY + dy * dist ~/ len);
  }

  // ───────────────────────── Recherches ─────────────────────────

  void _research() {
    for (final e in _done.entries) {
      for (final b in e.value) {
        if (!b.complete || b.queue.isNotEmpty || b.def.researches.isEmpty) {
          continue;
        }
        for (final t in b.def.researches) {
          final def = w.defs.tech(t);
          if (p.hasTech(def.index) || def.age > p.age) continue;
          // Les améliorations de récolte n'ont d'intérêt qu'avec des ouvriers.
          if (def.effects.any((x) => x.stat == 'gather' || x.stat == 'carry') &&
              _villagers.length < 10) {
            continue;
          }
          // Les améliorations militaires attendent une armée.
          if (def.effects.any(
                (x) => x.stat != 'gather' && x.stat != 'carry',
              ) &&
              _army.length < 4) {
            continue;
          }
          if (!_canSpend(def.cost)) continue;
          _spend(def.cost);
          _send(ResearchCmd(id, b.id, t));
          break;
        }
      }
    }
  }

  // ───────────────────────── Armée ─────────────────────────

  void _army2() {
    if (_tc == null) return;
    final rally = _stagingPoint();
    // Héros.
    if (diff.useHero && p.clan >= 0) {
      final heroId = w.defs.clans[p.clan].hero;
      final hero = w.defs.unit(heroId);
      final alive = _mine.any((u) => u.def.isHero);
      var queued = false;
      for (final b in _done.values.expand((e) => e)) {
        if (b.queue.any(
          (q) => !q.isTech && !q.isAge && w.defs.units[q.defIndex].isHero,
        )) {
          queued = true;
        }
      }
      if (!alive && !queued && hero.age <= p.age) {
        for (final b in _done['altar'] ?? const <Building>[]) {
          final cost = unitCostFor(w, p, hero);
          if (b.queue.isEmpty && _canSpend(cost)) {
            _spend(cost);
            _send(TrainCmd(id, b.id, heroId));
            break;
          }
        }
      }
    }
    if (_saving && _army.length >= 3) return;

    // Composition de l'armée adverse vue jusqu'ici.
    var eInf = 0;
    var eArch = 0;
    var eCav = 0;
    for (final f in _foes) {
      if (f.def.classes.contains('cavalry')) {
        eCav++;
      } else if (f.def.classes.contains('archer')) {
        eArch++;
      } else if (f.def.classes.contains('infantry')) {
        eInf++;
      }
    }

    final counts = <String, int>{};
    for (final u in _mine) {
      counts[u.def.id] = (counts[u.def.id] ?? 0) + 1;
    }
    for (final b in _done.values.expand((e) => e)) {
      for (final q in b.queue) {
        if (!q.isTech && !q.isAge) {
          final d = w.defs.units[q.defIndex].id;
          counts[d] = (counts[d] ?? 0) + 1;
        }
      }
    }

    for (final e in _done.entries) {
      final bdef = w.defs.building(e.key);
      if (bdef.trains.isEmpty || bdef.townCenter) continue;
      for (final b in e.value) {
        final cap = budget[Res.food] > 400 && budget[Res.wood] > 300 ? 3 : 2;
        if (b.queue.length >= cap) continue;
        if (b.rallyX < 0) {
          _send(SetRallyCmd(id, b.id, rally.$1, rally.$2));
        }
        final pick = _chooseUnit(bdef, counts, eInf, eArch, eCav);
        if (pick == null) continue;
        _spend(pick.cost);
        _send(TrainCmd(id, b.id, pick.id));
        counts[pick.id] = (counts[pick.id] ?? 0) + 1;
      }
    }
  }

  UnitDef? _chooseUnit(
    BuildingDef b,
    Map<String, int> counts,
    int eInf,
    int eArch,
    int eCav,
  ) {
    UnitDef? best;
    var bestScore = 1 << 60;
    for (final uid in b.trains) {
      final u = w.defs.unit(uid);
      if (u.isHero || u.age > p.age) continue;
      if (u.clan.isNotEmpty &&
          (p.clan < 0 || w.defs.clans[p.clan].id != u.clan)) {
        continue;
      }
      if (!_canSpend(u.cost)) continue;
      // Poids relatif de chaque type d'unité (plus grand = plus produit).
      var weight = 10;
      if (u.classes.contains('cavalry')) {
        weight = 4 + pers.cavalry ~/ 6;
        if (eArch > eInf + eCav) weight += 8;
        if (eInf > eCav + eArch) weight -= 3;
      } else if (u.classes.contains('archer')) {
        weight = 8;
        if (eInf > eArch + eCav) weight += 6;
        if (eCav > eInf + eArch) weight -= 4;
      } else if (u.classes.contains('siege')) {
        final armySize = _army.length;
        if (armySize < 8) continue;
        weight = pers.siege ~/ 8;
        if (weight == 0) continue;
        if ((counts[u.id] ?? 0) * 5 > armySize) continue;
      } else if (u.classes.contains('infantry')) {
        weight = 10;
        if (eCav > eInf + eArch) weight += 10;
      }
      if (u.clan.isNotEmpty) weight += 6;
      if (u.id == 'royal_guard') weight = 6;
      if (weight < 1) weight = 1;
      final score = (counts[u.id] ?? 0) * 1000 ~/ weight;
      if (score < bestScore) {
        bestScore = score;
        best = u;
      }
    }
    return best;
  }

  (int, int) _stagingPoint() {
    final cx = w.map.width ~/ 2;
    final cy = w.map.height ~/ 2;
    final dx = cx - _homeX;
    final dy = cy - _homeY;
    final len = math.max(1, math.max(dx.abs(), dy.abs()));
    final x = (_homeX + dx * 9 ~/ len).clamp(1, w.map.width - 2);
    final y = (_homeY + dy * 9 ~/ len).clamp(1, w.map.height - 2);
    return (x, y);
  }

  // ───────────────────────── Tactique ─────────────────────────

  int _power(Unit u) => u.hp * (u.def.attack + 3);

  void _tactics() {
    if (_army.isEmpty) {
      if (p.aiMem[_Mem.attackState] == AiAttackState.marching) {
        p.aiMem[_Mem.attackState] = AiAttackState.retreating;
        p.aiMem[_Mem.retreatUntil] = w.tick + 300;
      }
      _useSpells(const <Unit>[]);
      return;
    }
    if (p.aiMem[_Mem.attackState] == AiAttackState.retreating &&
        w.tick >= p.aiMem[_Mem.retreatUntil]) {
      p.aiMem[_Mem.attackState] = AiAttackState.gathering;
    }

    // 1) Défense du territoire.
    final threats = _threatsNearBase();
    if (threats.isNotEmpty) {
      _defend(threats);
      _usePowers(_army);
      _useSpells(_army);
      return;
    }

    final waveSize = _waveSize();
    final state = p.aiMem[_Mem.attackState];
    if (state == AiAttackState.gathering) {
      _gather();
      if (_army.length >= waveSize && _gatheredEnough()) {
        _startWave();
      }
    } else if (state == AiAttackState.marching) {
      _marchAndFight(waveSize);
    }
    _usePowers(_army);
    _useSpells(_army);
  }

  int _waveSize() {
    final base = math.max(ai.attackMinArmy, pers.raidWave);
    final growth = math.min(30, p.aiMem[_Mem.waves] * 2);
    return (base + growth) * diff.attackWaveScale ~/ 100;
  }

  bool _gatheredEnough() {
    final s = _stagingPoint();
    var near = 0;
    for (final u in _army) {
      if ((u.tileX - s.$1).abs() < 12 && (u.tileY - s.$2).abs() < 12) near++;
    }
    return near * 100 >= _army.length * 60;
  }

  void _gather() {
    final s = _stagingPoint();
    final far = <int>[];
    for (final u in _army) {
      if (_claimed.contains(u.id)) continue;
      if (!u.isIdle) continue;
      if ((u.tileX - s.$1).abs() > 6 || (u.tileY - s.$2).abs() > 6) {
        far.add(u.id);
      }
    }
    if (far.isNotEmpty) _send(MoveCmd(id, far, s.$1, s.$2));
  }

  List<Unit> _threatsNearBase() {
    final out = <Unit>[];
    final radius = ai.defenseRadius;
    for (final f in _foes) {
      if (!f.def.military) continue;
      var near = _dist2(f.tileX, f.tileY, _homeX, _homeY) <= radius * radius;
      if (!near) {
        for (final b in _done.values.expand((e) => e)) {
          if (b.def.isField || b.def.isWall) continue;
          if (_dist2(f.tileX, f.tileY, b.tx, b.ty) <= 36) {
            near = true;
            break;
          }
        }
      }
      if (near) out.add(f);
    }
    return out;
  }

  void _defend(List<Unit> threats) {
    final byTarget = <int, List<int>>{};
    for (final u in _army) {
      if (_claimed.contains(u.id)) continue;
      if (u.def.classes.contains('siege')) continue;
      final t = _nearestOf(u, threats);
      if (t == null) continue;
      final o = u.order;
      if (o != null && o.kind == OrderKind.attack && o.a == t.id) continue;
      (byTarget[t.id] ??= <int>[]).add(u.id);
    }
    byTarget.forEach((target, ids) => _send(AttackCmd(id, ids, target)));
    // Attaquée chez elle, l'IA ne lance pas de vague.
    if (p.aiMem[_Mem.attackState] == AiAttackState.marching) {
      p.aiMem[_Mem.attackState] = AiAttackState.gathering;
    }
  }

  Unit? _nearestOf(Unit from, List<Unit> list) {
    Unit? best;
    var bestD = 1 << 60;
    for (final f in list) {
      final d = _dist2(from.tileX, from.tileY, f.tileX, f.tileY);
      if (d < bestD || (d == bestD && best != null && f.id < best.id)) {
        bestD = d;
        best = f;
      }
    }
    return best;
  }

  void _startWave() {
    final target = _pickTarget();
    if (target == null) return;
    p.aiMem[_Mem.attackState] = AiAttackState.marching;
    p.aiMem[_Mem.targetX] = target.$1;
    p.aiMem[_Mem.targetY] = target.$2;
    p.aiMem[_Mem.waves]++;
  }

  /// Cible la plus proche : bâtiment adverse connu, sinon position de départ
  /// d'un adversaire encore en jeu.
  (int, int)? _pickTarget() {
    (int, int)? best;
    var bestD = 1 << 60;
    for (final b in _foeBuildings) {
      if (b.def.isWall) continue;
      final d = _dist2(b.tx, b.ty, _homeX, _homeY);
      final weight = b.def.vital ? d : d + 400;
      if (weight < bestD) {
        bestD = weight;
        best = (b.tx, b.ty);
      }
    }
    if (best != null) return best;
    for (final o in w.players) {
      if (o.defeated || !hostile(w, id, o.id)) continue;
      final d = _dist2(o.startX, o.startY, _homeX, _homeY);
      if (d < bestD) {
        bestD = d;
        best = (o.startX, o.startY);
      }
    }
    return best;
  }

  void _marchAndFight(int waveSize) {
    var tx = p.aiMem[_Mem.targetX];
    var ty = p.aiMem[_Mem.targetY];
    // La cible a-t-elle disparu ? On en reprend une.
    if (!_buildingAt(tx, ty)) {
      final t = _pickTarget();
      if (t == null) {
        p.aiMem[_Mem.attackState] = AiAttackState.gathering;
        return;
      }
      tx = t.$1;
      ty = t.$2;
      p.aiMem[_Mem.targetX] = tx;
      p.aiMem[_Mem.targetY] = ty;
    }
    // Retraite si la bataille est perdue d'avance.
    var cx = 0;
    var cy = 0;
    for (final u in _army) {
      cx += u.tileX;
      cy += u.tileY;
    }
    cx ~/= _army.length;
    cy ~/= _army.length;
    var myPower = 0;
    for (final u in _army) {
      myPower += _power(u);
    }
    var foePower = 0;
    final nearFoes = <Unit>[];
    for (final f in _foes) {
      if (_dist2(f.tileX, f.tileY, cx, cy) <= 12 * 12) {
        nearFoes.add(f);
        if (f.def.military) foePower += _power(f);
      }
    }
    for (final b in _foeBuildings) {
      if (b.def.attack > 0 && _dist2(b.tx, b.ty, cx, cy) <= 12 * 12) {
        foePower += b.hp * b.def.attack ~/ 2;
      }
    }
    final broken = _army.length * 3 < waveSize;
    final outmatched =
        foePower > 0 && myPower * 100 < foePower * ai.retreatRatioPercent;
    if (broken || outmatched) {
      p.aiMem[_Mem.attackState] = AiAttackState.retreating;
      p.aiMem[_Mem.retreatUntil] = w.tick + 600;
      _send(MoveCmd(id, _army.map((u) => u.id).toList(), _homeX, _homeY));
      return;
    }

    final military = nearFoes.where((f) => f.def.military).toList();
    final byTarget = <int, List<int>>{};
    final movers = <int>[];
    for (final u in _army) {
      if (_claimed.contains(u.id)) continue;
      final siege = u.def.classes.contains('siege');
      Unit? foe;
      if (!siege) foe = _nearestWithin(u, military, 9);
      int? targetId;
      if (foe != null) {
        targetId = foe.id;
      } else {
        final b = _nearestFoeBuilding(u, siege ? 12 : 14);
        if (b != null) targetId = b.id;
        if (targetId == null && !siege) {
          final civ = _nearestWithin(u, nearFoes, 9);
          if (civ != null) targetId = civ.id;
        }
      }
      if (targetId != null) {
        final o = u.order;
        if (o != null && o.kind == OrderKind.attack && o.a == targetId) {
          continue;
        }
        (byTarget[targetId] ??= <int>[]).add(u.id);
      } else {
        final o = u.order;
        final goingThere =
            o != null &&
            o.kind == OrderKind.move &&
            (o.a - tx).abs() <= 2 &&
            (o.b - ty).abs() <= 2;
        if (!goingThere) movers.add(u.id);
      }
    }
    byTarget.forEach((target, ids) => _send(AttackCmd(id, ids, target)));
    if (movers.isNotEmpty) _send(MoveCmd(id, movers, tx, ty));
  }

  bool _buildingAt(int tx, int ty) {
    if (!w.map.inBounds(tx, ty)) return false;
    final occ = w.map.occupant[w.map.index(tx, ty)];
    final b = w.buildings[occ];
    if (b != null) return hostile(w, id, b.owner);
    // Position de départ non encore explorée : on s'y rend.
    for (final o in w.players) {
      if (!o.defeated &&
          hostile(w, id, o.id) &&
          o.startX == tx &&
          o.startY == ty) {
        return p.explored[w.map.index(tx, ty)] == 0 || _foeBuildings.isNotEmpty;
      }
    }
    return false;
  }

  Unit? _nearestWithin(Unit u, List<Unit> list, int tiles) {
    Unit? best;
    var bestD = tiles * tiles + 1;
    for (final f in list) {
      final d = _dist2(u.tileX, u.tileY, f.tileX, f.tileY);
      if (d < bestD || (d == bestD && best != null && f.id < best.id)) {
        bestD = d;
        best = f;
      }
    }
    return best;
  }

  Building? _nearestFoeBuilding(Unit u, int tiles) {
    Building? best;
    var bestD = tiles * tiles + 1;
    for (final b in _foeBuildings) {
      if (b.def.isWall) continue;
      final d = _dist2(
        u.tileX,
        u.tileY,
        b.tx + b.def.width ~/ 2,
        b.ty + b.def.height ~/ 2,
      );
      // Les défenses armées d'abord.
      final score = b.def.attack > 0 ? d ~/ 2 : d;
      if (score < bestD) {
        bestD = score;
        best = b;
      }
    }
    return best;
  }

  // ───────────────────────── Pouvoirs et sorts ─────────────────────────

  void _usePowers(List<Unit> units) {
    if (!diff.usePowers) return;
    for (final u in units) {
      if (u.def.powers.isEmpty || isStunned(u) || _claimed.contains(u.id)) {
        continue;
      }
      for (var slot = 0; slot < u.def.powers.length && slot < 2; slot++) {
        final pd = w.defs.power(u.def.powers[slot]);
        if (pd.aura || pd.isSpell || pd.age > p.age || u.powerCd[slot] > 0) {
          continue;
        }
        final cmd = _planPower(u, slot, pd);
        if (cmd != null) {
          _send(cmd);
          break;
        }
      }
    }
  }

  PowerCmd? _planPower(Unit u, int slot, PowerDef pd) {
    final radiusTiles = math.max(1, pd.radius ~/ 1000);
    final engage = pd.target == PowerTarget.self ? radiusTiles + 3 : 8;
    final nearFoes = <Unit>[
      for (final f in _foes)
        if (f.def.military &&
            _dist2(u.tileX, u.tileY, f.tileX, f.tileY) <= engage * engage)
          f,
    ];
    final ultimate = slot == 1;
    final need = ultimate ? 4 : 2;
    switch (pd.target) {
      case PowerTarget.self:
        final offensive = pd.affects == PowerAffects.enemies;
        if (offensive) {
          return nearFoes.length >= need ? PowerCmd(id, u.id, slot) : null;
        }
        // Soutien : utile au contact de l'ennemi.
        return nearFoes.length >= (u.def.classes.contains('hero') ? 3 : 1)
            ? PowerCmd(id, u.id, slot)
            : null;
      case PowerTarget.unit:
        final t = _nearestWithin(u, nearFoes, pd.rangeTiles);
        if (t == null) return null;
        return PowerCmd(id, u.id, slot, target: t.id);
      case PowerTarget.ground:
        final inRange = <Unit>[
          for (final f in nearFoes)
            if (_dist2(u.tileX, u.tileY, f.tileX, f.tileY) <=
                pd.rangeTiles * pd.rangeTiles)
              f,
        ];
        if (inRange.length < need) return null;
        var cx = 0;
        var cy = 0;
        for (final f in inRange) {
          cx += f.tileX;
          cy += f.tileY;
        }
        return PowerCmd(
          id,
          u.id,
          slot,
          x: cx ~/ inRange.length,
          y: cy ~/ inRange.length,
        );
    }
  }

  void _useSpells(List<Unit> army) {
    if (!diff.usePowers) return;
    final foes = _foes.where((f) => f.def.military).toList();
    if (foes.isEmpty) return;
    for (final pd in w.defs.powers) {
      if (!pd.isSpell || p.drum < pd.drumCost || p.spellCd[pd.index] > 0) {
        continue;
      }
      final r = math.max(1, pd.radius ~/ 1000);
      final pool = pd.affects == PowerAffects.enemies
          ? foes
          : army
                .where((u) => u.hp * 2 < u.maxHp || pd.id != 'heal_spell')
                .toList();
      if (pool.length < 3) continue;
      // Case la plus dense.
      (int, int)? best;
      var bestN = 0;
      for (final c in pool) {
        var n = 0;
        for (final o in pool) {
          if (_dist2(c.tileX, c.tileY, o.tileX, o.tileY) <= r * r) n++;
        }
        if (n > bestN) {
          bestN = n;
          best = (c.tileX, c.tileY);
        }
      }
      if (best == null || bestN < 3) continue;
      // Les sorts de soutien exigent un combat en cours.
      if (pd.affects == PowerAffects.allies) {
        final fighting = army.any(
          (u) =>
              foes.any((f) => _dist2(u.tileX, u.tileY, f.tileX, f.tileY) <= 36),
        );
        if (!fighting) continue;
      }
      _send(SpellCmd(id, pd.index, best.$1, best.$2));
      return;
    }
  }

  // ───────────────────────── Chien de garde ─────────────────────────

  /// Aucun progrès (récolte, production, construction, dégâts) pendant
  /// `watchdogSeconds` : plan de secours.
  void _watchdog() {
    final s = p.stats;
    final score =
        s.totalGathered ~/ 4 +
        s.unitsTrained * 20 +
        s.buildingsBuilt * 30 +
        s.damageDealt +
        s.researches * 40 +
        _villagers.length;
    if (score != p.aiMem[_Mem.score]) {
      p.aiMem[_Mem.score] = score;
      p.aiMem[_Mem.scoreTick] = w.tick;
      return;
    }
    if (w.tick - p.aiMem[_Mem.scoreTick] < ai.watchdogTicks) return;
    p.aiMem[_Mem.scoreTick] = w.tick;
    p.aiMem[_Mem.watchdog]++;
    // 1) Remet tout le monde au travail.
    final stopIds = <int>[
      for (final u in _villagers)
        if (!_claimed.contains(u.id)) u.id,
    ];
    if (stopIds.isNotEmpty) _send(StopCmd(id, stopIds));
    // 2) Plus de centre-ville : on en rebâtit un.
    if (_tc == null) _rebuildTownCenter();
    // 3) Une armée inactive part à l'attaque.
    if (_army.length >= 3) {
      p.aiMem[_Mem.attackState] = AiAttackState.gathering;
      final t = _pickTarget();
      if (t != null) {
        p.aiMem[_Mem.attackState] = AiAttackState.marching;
        p.aiMem[_Mem.targetX] = t.$1;
        p.aiMem[_Mem.targetY] = t.$2;
        _send(
          MoveCmd(id, _army.map((u) => u.id).toList(), t.$1, t.$2),
        );
      }
    }
  }
}
