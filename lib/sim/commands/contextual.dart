import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/systems/economy.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Traduit un clic droit / un appui sur une cible en commandes (§9.1) :
/// sol → déplacer, ressource → récolter, ennemi → attaquer, bâtiment allié →
/// construire / réparer / cultiver / garnison.
///
/// [targetId] vaut -1 pour le sol. [queue] correspond à Maj+clic droit.
/// L'interface ne modifie jamais l'état : elle n'émet que ces commandes.
List<Command> contextualCommands(
  World w,
  int owner,
  List<int> selected, {
  required int tx,
  required int ty,
  int targetId = -1,
  bool queue = false,
}) {
  final units = ownedUnits(w, owner, selected);
  if (units.isEmpty) return const <Command>[];
  final villagers = <int>[
    for (final u in units)
      if (u.def.villager) u.id,
  ];
  final fighters = <int>[
    for (final u in units)
      if (u.def.attack > 0 && !u.def.villager) u.id,
  ];
  final all = <int>[for (final u in units) u.id];
  final move = MoveCmd(owner, all, tx, ty, queue: queue);

  if (targetId < 0) return <Command>[move];

  // Ennemi : tous ceux qui peuvent frapper attaquent (les villageois seuls
  // ne se jettent pas dans la mêlée s'il y a des soldats).
  if (isEnemyTarget(w, owner, targetId)) {
    final attackers = fighters.isNotEmpty
        ? fighters
        : <int>[
            for (final u in units)
              if (u.def.attack > 0) u.id,
          ];
    if (attackers.isEmpty) return <Command>[move];
    final rest = <int>[
      for (final id in all)
        if (!attackers.contains(id)) id,
    ];
    return <Command>[
      AttackCmd(owner, attackers, targetId, queue: queue),
      if (rest.isNotEmpty) MoveCmd(owner, rest, tx, ty, queue: queue),
    ];
  }

  // Ressource.
  if (w.nodes.containsKey(targetId)) {
    if (villagers.isEmpty) return <Command>[move];
    final others = <int>[
      for (final id in all)
        if (!villagers.contains(id)) id,
    ];
    return <Command>[
      GatherCmd(owner, villagers, targetId, queue: queue),
      if (others.isNotEmpty) MoveCmd(owner, others, tx, ty, queue: queue),
    ];
  }

  // Bâtiment allié.
  final b = w.buildings[targetId];
  if (b != null && b.owner == owner) {
    if (villagers.isNotEmpty) {
      if (!b.complete || (b.complete && b.hp < b.maxHp)) {
        final others = <int>[
          for (final id in all)
            if (!villagers.contains(id)) id,
        ];
        return <Command>[
          RepairCmd(owner, villagers, b.id, queue: queue),
          if (others.isNotEmpty) MoveCmd(owner, others, tx, ty, queue: queue),
        ];
      }
      if (b.isField) {
        return <Command>[GatherCmd(owner, villagers, b.id, queue: queue)];
      }
    }
    if (b.complete && b.def.garrison > 0) {
      return <Command>[GarrisonCmd(owner, all, b.id)];
    }
  }
  return <Command>[move];
}

/// Point de ralliement contextuel d'un bâtiment (clic droit avec le bâtiment
/// sélectionné) : sur une ressource, les villageois produits récoltent.
Command rallyCommand(
  World w,
  int owner,
  int buildingId, {
  required int tx,
  required int ty,
  int targetId = -1,
}) {
  final valid = targetId >= 0 && w.exists(targetId);
  return SetRallyCmd(owner, buildingId, tx, ty, valid ? targetId : -1);
}

/// Identifiant de l'entité sous la case (bâtiment/ressource) ou -1.
int entityAtTile(World w, int tx, int ty) {
  if (!w.map.inBounds(tx, ty)) return -1;
  final occ = w.map.occupant[w.map.index(tx, ty)];
  if (occ != 0) return occ;
  return -1;
}

/// Unité vivante la plus proche d'une position (virgule fixe) dans un rayon,
/// utile pour la tolérance de toucher. Les unités garnisonnées sont ignorées.
Unit? unitNear(World w, int fxX, int fxY, int radiusFx, {int? excludeOwner}) {
  Unit? best;
  var bestD = radiusFx * radiusFx;
  for (final u in w.units.values) {
    if (!u.alive || u.state == UnitState.garrisoned) continue;
    if (excludeOwner != null && u.owner == excludeOwner) continue;
    final dx = u.x - fxX;
    final dy = u.y - fxY;
    final d = dx * dx + dy * dy;
    if (d < bestD || (d == bestD && best != null && u.id < best.id)) {
      bestD = d;
      best = u;
    }
  }
  return best;
}
