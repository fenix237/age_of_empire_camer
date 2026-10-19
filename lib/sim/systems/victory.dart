import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/player.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Modes de victoire.
abstract final class VictoryMode {
  static const int none = 0;

  /// Détruire tous les bâtiments vitaux (production) adverses.
  static const int conquest = 1;

  /// Détruire tous les centres-villes adverses.
  static const int townCenters = 2;
}

bool _vital(World w, Building b) =>
    w.victoryMode == VictoryMode.townCenters ? b.def.townCenter : b.def.vital;

/// Vérifie les défaites et la victoire (toutes les secondes de jeu).
///
/// Un joueur est éliminé quand il n'a plus de bâtiment vital et plus de
/// villageois pour en rebâtir, ou après `straggleSeconds` sans bâtiment
/// vital. Une reddition élimine immédiatement. Quand il ne reste qu'une
/// équipe, la partie est terminée ; si tout le monde tombe au même tick :
/// égalité.
void updateVictory(World w) {
  if (w.victoryMode == VictoryMode.none ||
      w.gameOver ||
      w.players.length < 2 ||
      w.tick % 10 != 0) {
    return;
  }
  final straggle = w.balance.combat.straggleSeconds * 10;
  final vital = List<bool>.filled(w.players.length, false);
  final villagers = List<bool>.filled(w.players.length, false);
  for (final b in w.buildings.values) {
    if (_vital(w, b)) vital[b.owner] = true;
  }
  for (final u in w.units.values) {
    if (u.alive && u.def.villager) villagers[u.owner] = true;
  }
  final falling = <Player>[];
  for (final p in w.players) {
    if (p.defeated) continue;
    if (p.resigned) {
      falling.add(p);
      continue;
    }
    if (vital[p.id]) {
      p.noVitalSince = -1;
      continue;
    }
    if (p.noVitalSince < 0) p.noVitalSince = w.tick;
    if (!villagers[p.id] || w.tick - p.noVitalSince >= straggle) {
      falling.add(p);
    }
  }
  for (final p in falling) {
    _defeat(w, p);
  }
  final alive = <int>{
    for (final p in w.players)
      if (!p.defeated) p.team,
  };
  if (alive.length <= 1) {
    w.gameOver = true;
    w.winnerTeam = alive.isEmpty ? -2 : alive.first;
  }
}

void _defeat(World w, Player p) {
  p.defeated = true;
  p.defeatTick = w.tick;
  for (final u in List<Unit>.of(w.units.values)) {
    if (u.owner == p.id && u.alive) w.killUnit(u);
  }
  for (final b in List<Building>.of(w.buildings.values)) {
    if (b.owner == p.id) {
      b.queue.clear();
      w.removeBuilding(b, destroyed: false);
    }
  }
  w.events.add(GameEvent(EventType.playerDefeated, p.id, p.id));
}
