import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/core/vec2.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';

/// États d'une unité (machine à états explicite, §7.3 de l'analyse).
enum UnitState {
  idle,
  moving,
  gathering,
  building,
  attacking,
  garrisoned,
  dead,
}

/// Transitions autorisées. Toute autre transition est une anomalie.
const Map<UnitState, Set<UnitState>> allowedTransitions =
    <UnitState, Set<UnitState>>{
      UnitState.idle: <UnitState>{
        UnitState.moving,
        UnitState.gathering,
        UnitState.building,
        UnitState.attacking,
        UnitState.garrisoned,
        UnitState.dead,
      },
      UnitState.moving: <UnitState>{
        UnitState.idle,
        UnitState.gathering,
        UnitState.building,
        UnitState.attacking,
        UnitState.garrisoned,
        UnitState.dead,
      },
      UnitState.gathering: <UnitState>{
        UnitState.idle,
        UnitState.moving,
        UnitState.building,
        UnitState.attacking,
        UnitState.garrisoned,
        UnitState.dead,
      },
      UnitState.building: <UnitState>{
        UnitState.idle,
        UnitState.moving,
        UnitState.gathering,
        UnitState.attacking,
        UnitState.garrisoned,
        UnitState.dead,
      },
      UnitState.attacking: <UnitState>{
        UnitState.idle,
        UnitState.moving,
        UnitState.gathering,
        UnitState.building,
        UnitState.garrisoned,
        UnitState.dead,
      },
      UnitState.garrisoned: <UnitState>{UnitState.idle, UnitState.dead},
      UnitState.dead: <UnitState>{},
    };

enum Stance { aggressive, defensive, passive, follow }

/// Sous-phase d'une activité (récolte, construction…).
enum Phase { approach, work, returning }

/// Effet temporaire actif sur une unité.
class ActiveEffect {
  ActiveEffect(
    this.kind,
    this.power,
    this.remaining,
    this.value, [
    this.src = -1,
  ]);

  final EffectKind kind;

  /// Joueur à l'origine de l'effet (crédit des dégâts sur la durée).
  final int src;

  /// Indice du pouvoir source (-1 : coup spécial) : un même pouvoir ne se
  /// cumule jamais avec lui-même, il rafraîchit sa durée.
  final int power;
  int remaining;
  int value;

  List<int> toJson() => <int>[kind.index, power, remaining, value, src];

  static ActiveEffect fromJson(Object? j) {
    final l = j! as List<dynamic>;
    return ActiveEffect(
      EffectKind.values[l[0] as int],
      l[1] as int,
      l[2] as int,
      l[3] as int,
      l[4] as int,
    );
  }
}

class Unit {
  Unit({
    required this.id,
    required this.def,
    required this.owner,
    required this.x,
    required this.y,
  }) : hp = def.hp,
       maxHp = def.hp,
       px = x,
       py = y;

  final int id;
  final UnitDef def;
  final int owner;

  /// Position en virgule fixe (1 case = 256).
  int x;
  int y;

  /// Position au tick précédent (interpolation de rendu, hors hash).
  int px;
  int py;

  int hp;

  /// PV maximum (peut dépasser ceux de la définition via les recherches).
  int maxHp;
  UnitState state = UnitState.idle;
  Stance stance = Stance.aggressive;
  Phase phase = Phase.approach;

  final List<Order> orders = <Order>[];

  /// Chemin en indices de case ; [pathIdx] = prochain point.
  List<int> path = <int>[];
  int pathIdx = 0;
  bool pathPending = false;

  /// Le chemin actuel est partiel (objectif inaccessible).
  bool pathPartial = false;
  int pathVersion = -1;
  int flowId = -1;
  int stuckTicks = 0;
  int cooldown = 0;

  int carryRes = -1;
  int carryAmt = 0;
  int gatherProgress = 0;
  int targetId = -1;
  int lastTargetId = -1;
  int lastTargetX = 0;
  int lastTargetY = 0;
  int dropOffId = -1;
  int garrisonIn = -1;
  int followId = -1;

  /// Plafond de vitesse imposé par le groupe (0 = aucun), en fx/tick.
  int speedCap = 0;

  /// Rayon d'arrivée (cases) de l'ordre de déplacement courant.
  int moveReach = 0;

  /// Ressource en cours de récolte (-1 = aucune).
  int gatherRes = -1;

  /// A avancé ce tick (transitoire, hors sauvegarde).
  bool traveling = false;

  /// Effets actifs (ordre d'application = ordre de liste).
  final List<ActiveEffect> effects = <ActiveEffect>[];

  /// Temps de recharge restant des pouvoirs de la définition (ticks).
  final List<int> powerCd = <int>[0, 0, 0];

  /// Case de départ d'une poursuite déclenchée automatiquement : au-delà de
  /// la laisse, l'unité abandonne et revient.
  int homeX = 0;
  int homeY = 0;
  bool leashed = false;

  /// Immunité aux étourdissements jusqu'à ce tick (après un étourdissement).
  int stunImmuneUntil = 0;

  Vec2 get pos => Vec2(x, y);
  int get tileX => Fx.toInt(x);
  int get tileY => Fx.toInt(y);
  bool get alive => state != UnitState.dead;
  bool get isIdle => state == UnitState.idle;
  Order? get order => orders.isEmpty ? null : orders.first;

  Res? get carryType => carryRes < 0 ? null : Res.values[carryRes];

  void clearPath() {
    path = <int>[];
    pathIdx = 0;
    pathPending = false;
    pathPartial = false;
    pathVersion = -1;
    flowId = -1;
    stuckTicks = 0;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'def': def.index,
    'owner': owner,
    'x': x,
    'y': y,
    'hp': hp,
    'maxhp': maxHp,
    'state': state.index,
    'stance': stance.index,
    'phase': phase.index,
    'fx': <dynamic>[for (final e in effects) e.toJson()],
    'pcd': powerCd,
    'home': <int>[homeX, homeY, if (leashed) 1 else 0, stunImmuneUntil],
    'orders': <dynamic>[for (final o in orders) o.toJson()],
    'path': path,
    'pathIdx': pathIdx,
    'pending': pathPending,
    'partial': pathPartial,
    'pathVer': pathVersion,
    'flow': flowId,
    'stuck': stuckTicks,
    'cd': cooldown,
    'carryRes': carryRes,
    'carryAmt': carryAmt,
    'gprog': gatherProgress,
    'target': targetId,
    'lastTarget': lastTargetId,
    'ltx': lastTargetX,
    'lty': lastTargetY,
    'dropOff': dropOffId,
    'garrison': garrisonIn,
    'follow': followId,
    'cap': speedCap,
    'reach': moveReach,
    'gres': gatherRes,
  };

  static Unit fromJson(Map<String, dynamic> j, UnitDef def) {
    final u =
        Unit(
            id: j['id'] as int,
            def: def,
            owner: j['owner'] as int,
            x: j['x'] as int,
            y: j['y'] as int,
          )
          ..hp = j['hp'] as int
          ..maxHp = j['maxhp'] as int
          ..state = UnitState.values[j['state'] as int]
          ..stance = Stance.values[j['stance'] as int]
          ..phase = Phase.values[j['phase'] as int]
          ..path = List<int>.from(j['path'] as List<dynamic>)
          ..pathIdx = j['pathIdx'] as int
          ..pathPending = j['pending'] as bool
          ..pathPartial = j['partial'] as bool
          ..pathVersion = j['pathVer'] as int
          ..flowId = j['flow'] as int
          ..stuckTicks = j['stuck'] as int
          ..cooldown = j['cd'] as int
          ..carryRes = j['carryRes'] as int
          ..carryAmt = j['carryAmt'] as int
          ..gatherProgress = j['gprog'] as int
          ..targetId = j['target'] as int
          ..lastTargetId = j['lastTarget'] as int
          ..lastTargetX = j['ltx'] as int
          ..lastTargetY = j['lty'] as int
          ..dropOffId = j['dropOff'] as int
          ..garrisonIn = j['garrison'] as int
          ..followId = j['follow'] as int
          ..speedCap = j['cap'] as int
          ..moveReach = j['reach'] as int
          ..gatherRes = j['gres'] as int;
    for (final o in j['orders'] as List<dynamic>) {
      u.orders.add(Order.fromJson(o));
    }
    for (final e in j['fx'] as List<dynamic>) {
      u.effects.add(ActiveEffect.fromJson(e));
    }
    final pcd = List<int>.from(j['pcd'] as List<dynamic>);
    for (var i = 0; i < pcd.length && i < u.powerCd.length; i++) {
      u.powerCd[i] = pcd[i];
    }
    final home = List<int>.from(j['home'] as List<dynamic>);
    u
      ..homeX = home[0]
      ..homeY = home[1]
      ..leashed = home[2] == 1
      ..stunImmuneUntil = home[3];
    return u;
  }
}

/// Élément d'une file de production (unité ou recherche).
class QueueItem {
  QueueItem({
    required this.isTech,
    required this.defIndex,
    required this.remaining,
    required this.paid,
    this.isAge = false,
  });

  final bool isTech;

  /// Recherche de changement d'âge : [defIndex] est l'âge visé.
  final bool isAge;
  final int defIndex;
  int remaining;

  /// Coût payé à la mise en file (remboursable exactement).
  final Stock paid;

  Map<String, dynamic> toJson() => <String, dynamic>{
    't': isTech,
    'a': isAge,
    'd': defIndex,
    'r': remaining,
    'p': paid.toJson(),
  };

  static QueueItem fromJson(Map<String, dynamic> j) => QueueItem(
    isTech: j['t'] as bool,
    isAge: (j['a'] as bool?) ?? false,
    defIndex: j['d'] as int,
    remaining: j['r'] as int,
    paid: Stock.fromJson(j['p']),
  );
}

class Building {
  Building({
    required this.id,
    required this.def,
    required this.owner,
    required this.tx,
    required this.ty,
  }) : hp = 1,
       stock = def.fieldFood;

  final int id;
  final BuildingDef def;
  final int owner;

  /// Coin haut-gauche (case).
  final int tx;
  final int ty;
  int hp;
  bool complete = false;

  /// Progression de construction en millièmes de tick-bâtisseur.
  int progressMilli = 0;
  final List<QueueItem> queue = <QueueItem>[];
  int rallyX = -1;
  int rallyY = -1;
  int rallyTarget = -1;

  /// Nourriture restante (champs).
  int stock;
  final List<int> garrisoned = <int>[];

  /// Dette de réparation en millièmes, par ressource.
  final List<int> repairDebt = List<int>.filled(Res.values.length, 0);

  /// Recharge de l'attaque (tours, forteresse).
  int cooldown = 0;

  /// Nombre de bâtisseurs ayant travaillé ce tick (transitoire).
  int buildersThisTick = 0;
  int repairersThisTick = 0;

  int get maxHp => def.hp;
  int get totalBuildMilli => def.buildTicks * 1000;
  bool get isField => def.isField;

  /// Centre en virgule fixe.
  Vec2 get center => Vec2(
    (tx << Fx.bits) + (def.width << Fx.bits) ~/ 2,
    (ty << Fx.bits) + (def.height << Fx.bits) ~/ 2,
  );

  bool coversTile(int x, int y) =>
      x >= tx && y >= ty && x < tx + def.width && y < ty + def.height;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'def': def.index,
    'owner': owner,
    'tx': tx,
    'ty': ty,
    'hp': hp,
    'complete': complete,
    'progress': progressMilli,
    'queue': <dynamic>[for (final q in queue) q.toJson()],
    'rx': rallyX,
    'ry': rallyY,
    'rt': rallyTarget,
    'stock': stock,
    'cd': cooldown,
    'garrisoned': garrisoned,
    'debt': repairDebt,
  };

  static Building fromJson(Map<String, dynamic> j, BuildingDef def) {
    final b =
        Building(
            id: j['id'] as int,
            def: def,
            owner: j['owner'] as int,
            tx: j['tx'] as int,
            ty: j['ty'] as int,
          )
          ..hp = j['hp'] as int
          ..complete = j['complete'] as bool
          ..progressMilli = j['progress'] as int
          ..rallyX = j['rx'] as int
          ..rallyY = j['ry'] as int
          ..rallyTarget = j['rt'] as int
          ..stock = j['stock'] as int
          ..cooldown = j['cd'] as int;
    for (final q in j['queue'] as List<dynamic>) {
      b.queue.add(QueueItem.fromJson(q as Map<String, dynamic>));
    }
    b.garrisoned.addAll(List<int>.from(j['garrisoned'] as List<dynamic>));
    final debt = List<int>.from(j['debt'] as List<dynamic>);
    for (var i = 0; i < debt.length; i++) {
      b.repairDebt[i] = debt[i];
    }
    return b;
  }
}

/// Nœud de ressource (arbre, carrière…).
class ResourceNode {
  ResourceNode({
    required this.id,
    required this.def,
    required this.tx,
    required this.ty,
  }) : amount = def.amount;

  final int id;
  final ResourceDef def;
  final int tx;
  final int ty;
  int amount;

  Res get res => def.res;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'def': def.index,
    'tx': tx,
    'ty': ty,
    'amount': amount,
  };

  static ResourceNode fromJson(Map<String, dynamic> j, ResourceDef def) =>
      ResourceNode(
        id: j['id'] as int,
        def: def,
        tx: j['tx'] as int,
        ty: j['ty'] as int,
      )..amount = j['amount'] as int;
}

/// Projectile en vol (flèche, boulet). Entièrement en virgule fixe.
class Projectile {
  Projectile({
    required this.id,
    required this.owner,
    required this.srcId,
    required this.srcUnitDef,
    required this.srcBuildingDef,
    required this.targetId,
    required this.x,
    required this.y,
    required this.tx,
    required this.ty,
    required this.speed,
    required this.atkPercent,
    required this.ttl,
    this.firstHit = false,
  });

  final int id;
  final int owner;

  /// Identifiant de l'attaquant (peut être mort au moment de l'impact).
  final int srcId;

  /// Définition de l'attaquant (unité ou bâtiment, -1 si absent).
  final int srcUnitDef;
  final int srcBuildingDef;
  final int targetId;
  int x;
  int y;

  /// Dernière position connue de la cible.
  int tx;
  int ty;
  final int speed;

  /// Multiplicateur de dégâts figé au tir (recherches, effets, hauteur).
  final int atkPercent;
  int ttl;
  final bool firstHit;

  List<int> toJson() => <int>[
    id,
    owner,
    srcId,
    srcUnitDef,
    srcBuildingDef,
    targetId,
    x,
    y,
    tx,
    ty,
    speed,
    atkPercent,
    ttl,
    if (firstHit) 1 else 0,
  ];

  static Projectile fromJson(Object? j) {
    final l = List<int>.from(j! as List<dynamic>);
    return Projectile(
      id: l[0],
      owner: l[1],
      srcId: l[2],
      srcUnitDef: l[3],
      srcBuildingDef: l[4],
      targetId: l[5],
      x: l[6],
      y: l[7],
      tx: l[8],
      ty: l[9],
      speed: l[10],
      atkPercent: l[11],
      ttl: l[12],
      firstHit: l[13] == 1,
    );
  }
}
