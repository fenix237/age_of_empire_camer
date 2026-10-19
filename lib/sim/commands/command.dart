import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/combat.dart';
import 'package:age_of_empire_camer/sim/systems/construction.dart';
import 'package:age_of_empire_camer/sim/systems/economy.dart';
import 'package:age_of_empire_camer/sim/systems/production.dart';
import 'package:age_of_empire_camer/sim/systems/unit_system.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Résultat de validation/exécution d'une commande. Une commande invalide
/// n'a aucun effet et ne lève jamais d'exception.
enum CmdResult {
  ok,
  invalid,
  noUnits,
  notOwned,
  notFound,
  wrongTarget,
  cannotAfford,
  popCapped,
  queueFull,
  locked,
  badPlacement,
  unexplored,
  notComplete,
  nothingToDo,
  outOfRange,
}

/// Toute action du joueur (ou de l'IA) est une commande sérialisable.
sealed class Command {
  const Command(this.owner);

  final int owner;

  String get type;

  Map<String, dynamic> toJson();

  /// Valide puis applique. Ne doit modifier l'état qu'en cas de succès.
  CmdResult apply(World w);

  static Command fromJson(Map<String, dynamic> j) {
    final o = j['o'] as int;
    List<int> ids() => List<int>.from(j['ids'] as List<dynamic>);
    final q = (j['q'] as bool?) ?? false;
    switch (j['t'] as String) {
      case 'move':
        return MoveCmd(o, ids(), j['x'] as int, j['y'] as int, queue: q);
      case 'gather':
        return GatherCmd(o, ids(), j['target'] as int, queue: q);
      case 'attack':
        return AttackCmd(o, ids(), j['target'] as int, queue: q);
      case 'build':
        return BuildCmd(
          o,
          ids(),
          j['def'] as String,
          j['x'] as int,
          j['y'] as int,
          queue: q,
        );
      case 'repair':
        return RepairCmd(o, ids(), j['target'] as int, queue: q);
      case 'garrison':
        return GarrisonCmd(o, ids(), j['target'] as int);
      case 'ungarrison':
        return UngarrisonCmd(o, j['building'] as int);
      case 'stop':
        return StopCmd(o, ids());
      case 'stance':
        return SetStanceCmd(o, ids(), Stance.values[j['stance'] as int]);
      case 'train':
        return TrainCmd(
          o,
          j['building'] as int,
          j['unit'] as String,
          count: j['count'] as int,
        );
      case 'research':
        return ResearchCmd(o, j['building'] as int, j['tech'] as String);
      case 'cancel':
        return CancelQueueCmd(o, j['building'] as int, j['index'] as int);
      case 'rally':
        return SetRallyCmd(
          o,
          j['building'] as int,
          j['x'] as int,
          j['y'] as int,
          j['target'] as int,
        );
      case 'delete':
        return DeleteCmd(o, j['id'] as int);
      case 'exchange':
        return ExchangeCmd(
          o,
          Res.values[j['from'] as int],
          Res.values[j['to'] as int],
          j['amount'] as int,
        );
      case 'reseed':
        return ReseedCmd(o, j['id'] as int);
      case 'power':
        return PowerCmd(
          o,
          j['unit'] as int,
          j['slot'] as int,
          x: j['x'] as int,
          y: j['y'] as int,
          target: j['target'] as int,
        );
      case 'spell':
        return SpellCmd(o, j['power'] as int, j['x'] as int, j['y'] as int);
      case 'ageup':
        return AgeUpCmd(o, j['building'] as int);
      case 'resign':
        return ResignCmd(o);
      default:
        throw FormatException("Commande inconnue '${j['t']}'");
    }
  }
}

/// Unités vivantes et possédées par [owner] parmi [ids] (ordre conservé,
/// doublons ignorés).
List<Unit> ownedUnits(World w, int owner, List<int> ids) {
  final seen = <int>{};
  final out = <Unit>[];
  for (final id in ids) {
    final u = w.units[id];
    if (u != null && u.alive && u.owner == owner && seen.add(id)) out.add(u);
  }
  return out;
}

bool _validOwner(World w, int owner) => owner >= 0 && owner < w.players.length;

class MoveCmd extends Command {
  const MoveCmd(super.owner, this.ids, this.x, this.y, {this.queue = false});

  final List<int> ids;
  final int x;
  final int y;
  final bool queue;

  @override
  String get type => 'move';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'ids': ids,
    'x': x,
    'y': y,
    'q': queue,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    if (!w.map.inBounds(x, y)) return CmdResult.invalid;
    final us = ownedUnits(w, owner, ids);
    if (us.isEmpty) return CmdResult.noUnits;
    issueGroupMove(w, us, x, y, queue: queue);
    return CmdResult.ok;
  }
}

class GatherCmd extends Command {
  const GatherCmd(super.owner, this.ids, this.target, {this.queue = false});

  final List<int> ids;
  final int target;
  final bool queue;

  @override
  String get type => 'gather';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'ids': ids,
    'target': target,
    'q': queue,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final us = ownedUnits(w, owner, ids).where((u) => u.def.villager).toList();
    if (us.isEmpty) return CmdResult.noUnits;
    if (!canGatherFrom(w, owner, target)) return CmdResult.wrongTarget;
    for (final u in us) {
      issueOrder(w, u, Order.gather(target), queue: queue);
    }
    return CmdResult.ok;
  }
}

class AttackCmd extends Command {
  const AttackCmd(super.owner, this.ids, this.target, {this.queue = false});

  final List<int> ids;
  final int target;
  final bool queue;

  @override
  String get type => 'attack';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'ids': ids,
    'target': target,
    'q': queue,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final us = ownedUnits(
      w,
      owner,
      ids,
    ).where((u) => u.def.attack > 0).toList();
    if (us.isEmpty) return CmdResult.noUnits;
    if (!isEnemyTarget(w, owner, target)) return CmdResult.wrongTarget;
    for (final u in us) {
      issueOrder(w, u, Order.attack(target), queue: queue);
    }
    return CmdResult.ok;
  }
}

class BuildCmd extends Command {
  const BuildCmd(
    super.owner,
    this.ids,
    this.defId,
    this.x,
    this.y, {
    this.queue = false,
  });

  final List<int> ids;
  final String defId;
  final int x;
  final int y;
  final bool queue;

  @override
  String get type => 'build';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'ids': ids,
    'def': defId,
    'x': x,
    'y': y,
    'q': queue,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final def = w.defs.tryBuilding(defId);
    if (def == null) return CmdResult.notFound;
    final us = ownedUnits(w, owner, ids).where((u) => u.def.villager).toList();
    if (us.isEmpty) return CmdResult.noUnits;
    return placeBuilding(w, owner, def, x, y, us, queue: queue);
  }
}

class RepairCmd extends Command {
  const RepairCmd(super.owner, this.ids, this.target, {this.queue = false});

  final List<int> ids;
  final int target;
  final bool queue;

  @override
  String get type => 'repair';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'ids': ids,
    'target': target,
    'q': queue,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final us = ownedUnits(w, owner, ids).where((u) => u.def.villager).toList();
    if (us.isEmpty) return CmdResult.noUnits;
    final b = w.buildings[target];
    if (b == null || b.owner != owner) return CmdResult.wrongTarget;
    if (b.complete && b.hp >= b.maxHp) return CmdResult.nothingToDo;
    for (final u in us) {
      issueOrder(
        w,
        u,
        Order(b.complete ? OrderKind.repair : OrderKind.build, b.id),
        queue: queue,
      );
    }
    return CmdResult.ok;
  }
}

class GarrisonCmd extends Command {
  const GarrisonCmd(super.owner, this.ids, this.target);

  final List<int> ids;
  final int target;

  @override
  String get type => 'garrison';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'ids': ids,
    'target': target,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final us = ownedUnits(w, owner, ids);
    if (us.isEmpty) return CmdResult.noUnits;
    final b = w.buildings[target];
    if (b == null || b.owner != owner) return CmdResult.wrongTarget;
    if (!b.complete || b.def.garrison == 0) return CmdResult.wrongTarget;
    for (final u in us) {
      issueOrder(w, u, Order.garrison(b.id), queue: false);
    }
    return CmdResult.ok;
  }
}

class UngarrisonCmd extends Command {
  const UngarrisonCmd(super.owner, this.building);

  final int building;

  @override
  String get type => 'ungarrison';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'building': building,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final b = w.buildings[building];
    if (b == null || b.owner != owner) return CmdResult.notFound;
    if (b.garrisoned.isEmpty) return CmdResult.nothingToDo;
    for (final id in List<int>.of(b.garrisoned)) {
      final u = w.units[id];
      if (u != null) ejectUnit(w, u, b);
    }
    return CmdResult.ok;
  }
}

class StopCmd extends Command {
  const StopCmd(super.owner, this.ids);

  final List<int> ids;

  @override
  String get type => 'stop';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'ids': ids,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final us = ownedUnits(w, owner, ids);
    if (us.isEmpty) return CmdResult.noUnits;
    for (final u in us) {
      if (u.state == UnitState.garrisoned) continue;
      stopUnit(w, u);
    }
    return CmdResult.ok;
  }
}

class SetStanceCmd extends Command {
  const SetStanceCmd(super.owner, this.ids, this.stance);

  final List<int> ids;
  final Stance stance;

  @override
  String get type => 'stance';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'ids': ids,
    'stance': stance.index,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final us = ownedUnits(w, owner, ids);
    if (us.isEmpty) return CmdResult.noUnits;
    for (final u in us) {
      u.stance = stance;
    }
    return CmdResult.ok;
  }
}

class TrainCmd extends Command {
  const TrainCmd(super.owner, this.building, this.unit, {this.count = 1});

  final int building;
  final String unit;
  final int count;

  @override
  String get type => 'train';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'building': building,
    'unit': unit,
    'count': count,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    if (count < 1 || count > 20) return CmdResult.invalid;
    var last = CmdResult.ok;
    for (var i = 0; i < count; i++) {
      last = enqueueTrain(w, owner, building, unit);
      if (last != CmdResult.ok) return i > 0 ? CmdResult.ok : last;
    }
    return last;
  }
}

class ResearchCmd extends Command {
  const ResearchCmd(super.owner, this.building, this.tech);

  final int building;
  final String tech;

  @override
  String get type => 'research';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'building': building,
    'tech': tech,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    return enqueueResearch(w, owner, building, tech);
  }
}

class CancelQueueCmd extends Command {
  const CancelQueueCmd(super.owner, this.building, this.index);

  final int building;
  final int index;

  @override
  String get type => 'cancel';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'building': building,
    'index': index,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    return cancelQueueItem(w, owner, building, index);
  }
}

class SetRallyCmd extends Command {
  const SetRallyCmd(
    super.owner,
    this.building,
    this.x,
    this.y, [
    this.target = -1,
  ]);

  final int building;
  final int x;
  final int y;
  final int target;

  @override
  String get type => 'rally';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'building': building,
    'x': x,
    'y': y,
    'target': target,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final b = w.buildings[building];
    if (b == null || b.owner != owner) return CmdResult.notFound;
    if (!w.map.inBounds(x, y)) return CmdResult.invalid;
    b
      ..rallyX = x
      ..rallyY = y
      ..rallyTarget = target >= 0 && w.exists(target) ? target : -1;
    return CmdResult.ok;
  }
}

class DeleteCmd extends Command {
  const DeleteCmd(super.owner, this.id);

  final int id;

  @override
  String get type => 'delete';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'id': id,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final b = w.buildings[id];
    if (b != null) {
      if (b.owner != owner) return CmdResult.notOwned;
      deleteBuilding(w, b);
      return CmdResult.ok;
    }
    final u = w.units[id];
    if (u != null && u.alive) {
      if (u.owner != owner) return CmdResult.notOwned;
      w.killUnit(u);
      return CmdResult.ok;
    }
    return CmdResult.notFound;
  }
}

class ExchangeCmd extends Command {
  const ExchangeCmd(super.owner, this.from, this.to, this.amount);

  final Res from;
  final Res to;
  final int amount;

  @override
  String get type => 'exchange';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'from': from.index,
    'to': to.index,
    'amount': amount,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    return exchangeResources(w, owner, from, to, amount);
  }
}

class ReseedCmd extends Command {
  const ReseedCmd(super.owner, this.id);

  final int id;

  @override
  String get type => 'reseed';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'id': id,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    final b = w.buildings[id];
    if (b == null || b.owner != owner || !b.isField || !b.complete) {
      return CmdResult.wrongTarget;
    }
    return reseedField(w, b) ? CmdResult.ok : CmdResult.cannotAfford;
  }
}

/// Pouvoir d'une unité : [slot] 0 = pouvoir de base, 1 = ultime (héros).
class PowerCmd extends Command {
  const PowerCmd(
    super.owner,
    this.unit,
    this.slot, {
    this.x = 0,
    this.y = 0,
    this.target = -1,
  });

  final int unit;
  final int slot;
  final int x;
  final int y;
  final int target;

  @override
  String get type => 'power';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'unit': unit,
    'slot': slot,
    'x': x,
    'y': y,
    'target': target,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    return usePower(w, owner, unit, slot, x, y, target);
  }
}

/// Sort de bataille lancé sur une case (énergie du tambour).
class SpellCmd extends Command {
  const SpellCmd(super.owner, this.power, this.x, this.y);

  /// Indice du pouvoir dans `Defs.powers`.
  final int power;
  final int x;
  final int y;

  @override
  String get type => 'spell';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'power': power,
    'x': x,
    'y': y,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    return castSpell(w, owner, power, x, y);
  }
}

/// Lance la recherche du prochain âge dans le bâtiment indiqué.
class AgeUpCmd extends Command {
  const AgeUpCmd(super.owner, this.building);

  final int building;

  @override
  String get type => 'ageup';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    'o': owner,
    'building': building,
  };

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    return enqueueAgeUp(w, owner, building);
  }
}

/// Reddition : le joueur est éliminé au prochain contrôle de victoire.
class ResignCmd extends Command {
  const ResignCmd(super.owner);

  @override
  String get type => 'resign';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{'t': type, 'o': owner};

  @override
  CmdResult apply(World w) {
    if (!_validOwner(w, owner)) return CmdResult.invalid;
    w.players[owner].resigned = true;
    return CmdResult.ok;
  }
}
