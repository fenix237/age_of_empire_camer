import 'package:age_of_empire_camer/sim/ai/ai.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_runtime.dart';
import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/commands/journal.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/core/hashing.dart';
import 'package:age_of_empire_camer/sim/core/invariants.dart';
import 'package:age_of_empire_camer/sim/core/rng.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/pathfinding/astar.dart';
import 'package:age_of_empire_camer/sim/pathfinding/flow_field.dart';
import 'package:age_of_empire_camer/sim/systems/combat.dart';
import 'package:age_of_empire_camer/sim/systems/construction.dart';
import 'package:age_of_empire_camer/sim/systems/path_service.dart';
import 'package:age_of_empire_camer/sim/systems/production.dart';
import 'package:age_of_empire_camer/sim/systems/unit_system.dart';
import 'package:age_of_empire_camer/sim/systems/victory.dart';
import 'package:age_of_empire_camer/sim/systems/vision.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/game_map.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/player.dart';
import 'package:age_of_empire_camer/sim/world/spatial_hash.dart';

enum EventType {
  unitDied,
  buildingComplete,
  buildingDestroyed,
  unitTrained,
  researchDone,
  resourceDepleted,
  underAttack,
  commandRejected,
  ageAdvanced,
  playerDefeated,
}

/// Événement de jeu pour l'interface (alertes, sons). Non persistant.
class GameEvent {
  const GameEvent(this.type, this.owner, this.id, [this.x = 0, this.y = 0]);

  final EventType type;
  final int owner;
  final int id;
  final int x;
  final int y;
}

/// Monde de simulation : état complet, tick fixe, ordre de résolution
/// déterministe (entités traitées par identifiant croissant).
class World {
  World({
    required this.defs,
    required this.map,
    required this.seed,
    required int playerCount,
  }) : rng = Rng(seed),
       players = <Player>[
         for (var i = 0; i < playerCount; i++) Player(i, map.size),
       ],
       astar = AStar(map),
       spatial = SpatialHash(map.width, map.height) {
    paths = PathService(this);
    for (final p in players) {
      p.spellCd = List<int>.filled(defs.powers.length, 0);
    }
  }

  final Defs defs;
  final GameMap map;
  final int seed;
  Rng rng;
  int tick = 0;
  int _nextId = 1;
  int nextFlowId = 0;

  final List<Player> players;

  /// Insertion = ordre d'identifiant croissant (itération déterministe).
  final Map<int, Unit> units = <int, Unit>{};
  final Map<int, Building> buildings = <int, Building>{};
  final Map<int, ResourceNode> nodes = <int, ResourceNode>{};
  final Map<int, FlowField> flows = <int, FlowField>{};

  /// Projectiles en vol (flèches, boulets), par identifiant croissant.
  final Map<int, Projectile> projectiles = <int, Projectile>{};

  /// Règle de victoire : 0 = aucune (tests), 1 = conquête, 2 = centres-villes.
  int victoryMode = 0;

  /// Mission de campagne en cours (null en escarmouche).
  MissionRuntime? mission;

  /// État de mission lu dans une sauvegarde, en attente de sa définition
  /// (voir `attachMission`).
  Map<String, dynamic>? missionRaw;

  /// Les IA réfléchissent (désactivé pour rejouer un journal de commandes).
  bool aiEnabled = true;

  /// Équipe gagnante (-1 : partie en cours, -2 : égalité).
  int winnerTeam = -1;
  bool gameOver = false;

  /// File FIFO des unités en attente d'un calcul de chemin.
  final List<int> pathQueue = <int>[];

  final AStar astar;
  final SpatialHash spatial;
  late final PathService paths;

  final List<Command> _pending = <Command>[];
  final CommandJournal journal = CommandJournal();

  /// Événements du tick courant.
  final List<GameEvent> events = <GameEvent>[];

  /// Anomalies détectées (transitions illégales, invariants violés).
  final List<String> violations = <String>[];

  /// Hash d'état tous les `hashEveryTicks` : paires [tick, hash] aplaties.
  final List<int> hashLog = <int>[];
  static const int _hashLogCap = 8192;

  /// Incrémenté à chaque recalcul du brouillard (invalide les caches de rendu).
  int visionRevision = 0;

  /// Vérifie les invariants après chaque tick (tests, debug).
  bool checkInvariantsEachTick = false;

  /// Ids retirés pendant ce tick (nettoyage des références).
  final Set<int> _removed = <int>{};

  BalanceDef get balance => defs.balance;

  int newId() => _nextId++;
  int get nextIdValue => _nextId;

  // ───────────────────────── Création ─────────────────────────

  Unit spawnUnit(UnitDef def, int owner, int fxX, int fxY) {
    final u = Unit(id: newId(), def: def, owner: owner, x: fxX, y: fxY);
    final mhp = maxHpFor(this, owner, def);
    u
      ..maxHp = mhp
      ..hp = mhp;
    units[u.id] = u;
    players[owner].popUsed += def.pop;
    return u;
  }

  Building spawnBuilding(
    BuildingDef def,
    int owner,
    int tx,
    int ty, {
    bool complete = false,
  }) {
    final b = Building(id: newId(), def: def, owner: owner, tx: tx, ty: ty);
    if (complete) {
      b.complete = true;
      b.hp = def.hp;
      b.progressMilli = b.totalBuildMilli;
    }
    buildings[b.id] = b;
    map.setOccupant(tx, ty, def.width, def.height, b.id);
    return b;
  }

  ResourceNode spawnNode(ResourceDef def, int tx, int ty) {
    final n = ResourceNode(id: newId(), def: def, tx: tx, ty: ty);
    nodes[n.id] = n;
    map.setOccupant(tx, ty, 1, 1, n.id);
    return n;
  }

  // ───────────────────────── Requêtes ─────────────────────────

  bool exists(int id) =>
      units.containsKey(id) ||
      buildings.containsKey(id) ||
      nodes.containsKey(id);

  /// Rectangle (x, y, largeur, hauteur) en cases d'une entité, ou null.
  List<int>? rectOf(int id) {
    final b = buildings[id];
    if (b != null) return <int>[b.tx, b.ty, b.def.width, b.def.height];
    final n = nodes[id];
    if (n != null) return <int>[n.tx, n.ty, 1, 1];
    final u = units[id];
    if (u != null && u.alive) return <int>[u.tileX, u.tileY, 1, 1];
    return null;
  }

  /// Distance (virgule fixe) d'un point au rectangle de cases donné.
  static int distToRect(int px, int py, int tx, int ty, int w, int h) {
    final x0 = tx << Fx.bits;
    final y0 = ty << Fx.bits;
    final x1 = (tx + w) << Fx.bits;
    final y1 = (ty + h) << Fx.bits;
    final dx = px < x0 ? x0 - px : (px > x1 ? px - x1 : 0);
    final dy = py < y0 ? y0 - py : (py > y1 ? py - y1 : 0);
    return Fx.isqrt(dx * dx + dy * dy);
  }

  List<Unit> unitsOf(int owner) => <Unit>[
    for (final u in units.values)
      if (u.owner == owner) u,
  ];

  // ───────────────────────── Etats ─────────────────────────

  /// Change l'état d'une unité en vérifiant la table de transitions.
  void setState(Unit u, UnitState next) {
    if (u.state == next) return;
    if (!allowedTransitions[u.state]!.contains(next)) {
      violations.add(
        'Transition illégale ${u.state.name}→${next.name} (unité ${u.id})',
      );
      assert(false, 'Transition illégale ${u.state.name}→${next.name}');
      u.state = UnitState.idle;
      return;
    }
    u.state = next;
  }

  // ───────────────────────── Commandes ─────────────────────────

  void submit(Command c) => _pending.add(c);

  int get pendingCommandCount => _pending.length;

  // ───────────────────────── Boucle ─────────────────────────

  void step() {
    events.clear();
    recount();
    updateAi(this);

    if (_pending.isNotEmpty) {
      final batch = List<Command>.of(_pending);
      _pending.clear();
      for (final c in batch) {
        journal.record(tick, c);
        final r = c.apply(this);
        if (r != CmdResult.ok) {
          events.add(GameEvent(EventType.commandRejected, c.owner, r.index));
        }
      }
    }

    paths.processQueue();
    updateProduction(this);
    spatial.rebuild(units.values, units.length);

    for (final u in List<Unit>.of(units.values)) {
      if (u.alive) updateUnit(this, u);
    }
    updateBuildingCombat(this);
    updateProjectiles(this);
    updatePowers(this);
    finishConstruction(this);
    updateVictory(this);
    mission?.update(this);
    _cleanup();

    if (tick % balance.visionEveryTicks == 0) updateVision(this);
    _purgeFlows();

    tick++;
    if (tick % balance.hashEveryTicks == 0) {
      hashLog
        ..add(tick)
        ..add(stateHash());
      if (hashLog.length > _hashLogCap * 2) hashLog.removeRange(0, 2);
    }
    if (checkInvariantsEachTick) {
      final found = checkInvariants(this);
      if (found.isNotEmpty) {
        violations.addAll(found);
        assert(false, 'Invariants violés au tick $tick : ${found.first}');
      }
    }
  }

  /// Recalcule population courante et plafond (début de tick, après un
  /// chargement, après la création d'une partie).
  void recount() {
    for (final p in players) {
      p.popUsed = 0;
      p.popCap = 0;
    }
    for (final u in units.values) {
      if (u.alive) players[u.owner].popUsed += u.def.pop;
    }
    for (final b in buildings.values) {
      if (b.complete) players[b.owner].popCap += b.def.popBonus;
    }
    for (final p in players) {
      if (p.popCap > balance.maxPopulation) p.popCap = balance.maxPopulation;
    }
  }

  // ───────────────────────── Suppression ─────────────────────────

  /// Marque une unité comme morte (retirée à la fin du tick).
  void killUnit(Unit u) {
    if (!u.alive) return;
    if (u.garrisonIn >= 0) buildings[u.garrisonIn]?.garrisoned.remove(u.id);
    u.state = UnitState.dead;
    u.hp = 0;
    u.orders.clear();
    u.effects.clear();
    u.clearPath();
    final p = players[u.owner];
    p.stats.unitsLost++;
    if (u.def.isHero) {
      p.fallenHeroes.add(u.def.index);
      p.stats.heroDeaths++;
    }
    events.add(GameEvent(EventType.unitDied, u.owner, u.id, u.tileX, u.tileY));
  }

  /// Retire immédiatement un bâtiment (détruit ou supprimé).
  void removeBuilding(Building b, {required bool destroyed}) {
    buildings.remove(b.id);
    map.setOccupant(b.tx, b.ty, b.def.width, b.def.height, 0);
    _removed.add(b.id);
    for (final uid in List<int>.of(b.garrisoned)) {
      final u = units[uid];
      if (u != null) ejectUnit(this, u, b);
    }
    if (destroyed) {
      events.add(
        GameEvent(EventType.buildingDestroyed, b.owner, b.id, b.tx, b.ty),
      );
    }
  }

  void removeNode(ResourceNode n) {
    nodes.remove(n.id);
    map.setOccupant(n.tx, n.ty, 1, 1, 0);
    _removed.add(n.id);
    events.add(GameEvent(EventType.resourceDepleted, -1, n.id, n.tx, n.ty));
  }

  void _cleanup() {
    for (final u in List<Unit>.of(units.values)) {
      if (u.state == UnitState.dead) {
        units.remove(u.id);
        _removed.add(u.id);
      }
    }
    if (_removed.isEmpty) return;
    final removed = Set<int>.of(_removed);
    _removed.clear();
    for (final u in units.values) {
      purgeReferences(this, u, removed);
    }
    for (final b in buildings.values) {
      if (removed.contains(b.rallyTarget)) b.rallyTarget = -1;
      b.garrisoned.removeWhere(removed.contains);
    }
  }

  void _purgeFlows() {
    if (flows.isEmpty || tick % 20 != 0) return;
    final used = <int>{
      for (final u in units.values)
        if (u.flowId >= 0) u.flowId,
    };
    flows.removeWhere((id, _) => !used.contains(id));
  }

  // ───────────────────────── Hash ─────────────────────────

  int stateHash() {
    final h = StateHasher()
      ..addInt(tick)
      ..addInt(_nextId)
      ..addInts(rng.state)
      ..addInt(map.version);
    for (final p in players) {
      h
        ..addInt(p.id)
        ..addInt(p.age)
        ..addInts(p.stock.v)
        ..addInts(p.techs)
        ..addBytes(p.explored)
        ..addInt(p.clan)
        ..addInt(p.team)
        ..addInt(p.aiLevel)
        ..addInt(p.defeated ? 1 : 0)
        ..addInt(p.noVitalSince)
        ..addInt(p.drum)
        ..addInts(p.spellCd)
        ..addInts(p.fallenHeroes);
      if (p.locked.isNotEmpty) {
        h.addInts(<int>[
          for (final l in (p.locked.toList()..sort())) stableStringHash(l),
        ]);
      }
    }
    for (final u in units.values) {
      h
        ..addInt(u.id)
        ..addInt(u.def.index)
        ..addInt(u.owner)
        ..addInt(u.x)
        ..addInt(u.y)
        ..addInt(u.hp)
        ..addInt(u.state.index)
        ..addInt(u.stance.index)
        ..addInt(u.phase.index)
        ..addInt(u.pathIdx)
        ..addInt(u.path.length)
        ..addInt(u.pathPending ? 1 : 0)
        ..addInt(u.pathPartial ? 1 : 0)
        ..addInt(u.pathVersion)
        ..addInt(u.flowId)
        ..addInt(u.stuckTicks)
        ..addInt(u.cooldown)
        ..addInt(u.carryRes)
        ..addInt(u.carryAmt)
        ..addInt(u.gatherProgress)
        ..addInt(u.targetId)
        ..addInt(u.lastTargetId)
        ..addInt(u.dropOffId)
        ..addInt(u.garrisonIn)
        ..addInt(u.followId)
        ..addInt(u.speedCap)
        ..addInt(u.moveReach)
        ..addInt(u.gatherRes)
        ..addInt(u.maxHp)
        ..addInt(u.homeX)
        ..addInt(u.homeY)
        ..addInt(u.leashed ? 1 : 0)
        ..addInt(u.stunImmuneUntil)
        ..addInts(u.powerCd)
        ..addInt(u.effects.length)
        ..addInt(u.orders.length);
      for (final e in u.effects) {
        h
          ..addInt(e.kind.index)
          ..addInt(e.power)
          ..addInt(e.remaining)
          ..addInt(e.value);
      }
      for (final o in u.orders) {
        h
          ..addInt(o.kind.index)
          ..addInt(o.a)
          ..addInt(o.b);
      }
      if (u.path.isNotEmpty) h.addInt(u.path.last);
    }
    for (final b in buildings.values) {
      h
        ..addInt(b.id)
        ..addInt(b.def.index)
        ..addInt(b.owner)
        ..addInt(b.tx)
        ..addInt(b.ty)
        ..addInt(b.hp)
        ..addInt(b.complete ? 1 : 0)
        ..addInt(b.progressMilli)
        ..addInt(b.stock)
        ..addInt(b.cooldown)
        ..addInt(b.rallyX)
        ..addInt(b.rallyY)
        ..addInt(b.rallyTarget)
        ..addInts(b.garrisoned)
        ..addInts(b.repairDebt)
        ..addInt(b.queue.length);
      for (final q in b.queue) {
        h
          ..addInt(q.isTech ? 1 : 0)
          ..addInt(q.isAge ? 1 : 0)
          ..addInt(q.defIndex)
          ..addInt(q.remaining)
          ..addInts(q.paid.v);
      }
    }
    for (final n in nodes.values) {
      h
        ..addInt(n.id)
        ..addInt(n.def.index)
        ..addInt(n.amount);
    }
    for (final f in flows.values) {
      h
        ..addInt(f.id)
        ..addInt(f.goal.x0)
        ..addInt(f.goal.y0)
        ..addInt(f.goal.reach);
    }
    h.addInts(pathQueue);
    for (final pr in projectiles.values) {
      h.addInts(pr.toJson());
    }
    h
      ..addInt(victoryMode)
      ..addInt(winnerTeam)
      ..addInt(gameOver ? 1 : 0);
    mission?.hashInto(h);
    return h.value;
  }

  // ───────────────────────── Sérialisation ─────────────────────────

  static const int stateFormat = 2;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': stateFormat,
    'seed': seed,
    'tick': tick,
    'nextId': _nextId,
    'nextFlow': nextFlowId,
    'rng': rng.state,
    'map': map.toJson(),
    'players': <dynamic>[for (final p in players) p.toJson()],
    'units': <dynamic>[for (final u in units.values) u.toJson()],
    'buildings': <dynamic>[for (final b in buildings.values) b.toJson()],
    'nodes': <dynamic>[for (final n in nodes.values) n.toJson()],
    'flows': <dynamic>[
      for (final f in flows.values)
        <int>[f.id, f.goal.x0, f.goal.y0, f.goal.x1, f.goal.y1, f.goal.reach],
    ],
    'pathQueue': pathQueue,
    'projectiles': <dynamic>[for (final p in projectiles.values) p.toJson()],
    'victory': <int>[victoryMode, winnerTeam, if (gameOver) 1 else 0],
    if (mission != null)
      'mission': mission!.toJson()
    else if (missionRaw != null)
      'mission': missionRaw,
  };

  static World fromJson(Defs defs, Map<String, dynamic> j) {
    if (j['format'] != stateFormat) {
      throw DataException('save', 'format', 'format de monde non supporté');
    }
    final mapJson = j['map'] as Map<String, dynamic>;
    final map = GameMap.fromJson(mapJson, defs.terrain);
    final playersJson = j['players'] as List<dynamic>;
    final w = World(
      defs: defs,
      map: map,
      seed: j['seed'] as int,
      playerCount: 0,
    );
    w.players.clear();
    for (final p in playersJson) {
      w.players.add(
        Player.fromJson(p as Map<String, dynamic>, map.size, defs),
      );
    }
    w
      ..tick = j['tick'] as int
      .._nextId = j['nextId'] as int
      ..nextFlowId = j['nextFlow'] as int;
    final rs = List<int>.from(j['rng'] as List<dynamic>);
    w.rng = Rng.fromState(rs[0], rs[1]);
    for (final n in j['nodes'] as List<dynamic>) {
      final m = n as Map<String, dynamic>;
      final node = ResourceNode.fromJson(m, defs.resources[m['def'] as int]);
      w.nodes[node.id] = node;
      map.occupant[map.index(node.tx, node.ty)] = node.id;
    }
    for (final b in j['buildings'] as List<dynamic>) {
      final m = b as Map<String, dynamic>;
      final bld = Building.fromJson(m, defs.buildings[m['def'] as int]);
      w.buildings[bld.id] = bld;
      for (var y = bld.ty; y < bld.ty + bld.def.height; y++) {
        for (var x = bld.tx; x < bld.tx + bld.def.width; x++) {
          map.occupant[map.index(x, y)] = bld.id;
        }
      }
    }
    for (final u in j['units'] as List<dynamic>) {
      final m = u as Map<String, dynamic>;
      final unit = Unit.fromJson(m, defs.units[m['def'] as int]);
      w.units[unit.id] = unit;
    }
    for (final f in j['flows'] as List<dynamic>) {
      final l = List<int>.from(f as List<dynamic>);
      w.flows[l[0]] = FlowField(
        l[0],
        GoalRect(l[1], l[2], l[3], l[4], reach: l[5]),
      );
    }
    w.pathQueue.addAll(List<int>.from(j['pathQueue'] as List<dynamic>));
    for (final p in j['projectiles'] as List<dynamic>) {
      final pr = Projectile.fromJson(p);
      w.projectiles[pr.id] = pr;
    }
    final v = List<int>.from(j['victory'] as List<dynamic>);
    w
      ..victoryMode = v[0]
      ..winnerTeam = v[1]
      ..gameOver = v[2] == 1;
    w.missionRaw = j['mission'] as Map<String, dynamic>?;
    map.version = mapJson['version'] as int;
    w.recount();
    updateVision(w, mergeExplored: false);
    return w;
  }

  /// Ordre unique pour une unité (utilitaire de test/IA).
  void giveOrder(Unit u, Order order) =>
      issueOrder(this, u, order, queue: false);
}
