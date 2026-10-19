import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/production.dart';
import 'package:age_of_empire_camer/sim/systems/victory.dart';
import 'package:age_of_empire_camer/sim/systems/vision.dart';
import 'package:age_of_empire_camer/sim/world/map_generator.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Réglage d'un joueur au lancement d'une partie.
class PlayerSetup {
  const PlayerSetup({this.clan = 0, this.aiLevel = -1, this.team = -1});

  /// Indice du clan (`Defs.clans`).
  final int clan;

  /// -1 : joueur humain ; sinon indice de difficulté de l'IA.
  final int aiLevel;

  /// Équipe (-1 : seul dans sa propre équipe).
  final int team;
}

/// Crée une partie prête à jouer : carte générée, ressources, centre-ville
/// et villageois de départ pour chaque joueur. Sans [setups], les joueurs
/// n'ont ni clan ni IA (parties de test) ; avec, le clan donne ses bonus et
/// ses ressources de départ, l'IA pilote le joueur.
World createGame(
  Defs defs, {
  required int seed,
  int size = 64,
  int players = 2,
  int style = 0,
  List<PlayerSetup>? setups,
  Stock? startingResources,
  int victoryMode = VictoryMode.none,
}) {
  if (setups != null && setups.length != players) {
    throw ArgumentError.value(setups.length, 'setups', 'un par joueur');
  }
  final gen = MapGenerator.generate(
    defs,
    seed: seed,
    size: size,
    players: players,
    style: style,
  );
  final w = World(
    defs: defs,
    map: gen.map,
    seed: gen.seedUsed,
    playerCount: players,
  );
  for (final n in gen.nodes) {
    w.spawnNode(defs.resource(n.defId), n.x, n.y);
  }
  final tc = defs.buildings.firstWhere((b) => b.townCenter);
  final villager = defs.units.firstWhere((u) => u.villager);
  for (var i = 0; i < players; i++) {
    final s = gen.starts[i];
    final p = w.players[i]
      ..startX = s.x
      ..startY = s.y
      ..stock = (startingResources ?? defs.balance.startingResources).copy();
    if (setups != null) {
      final set = setups[i];
      p
        ..clan = set.clan.clamp(0, defs.clans.length - 1)
        ..team = set.team >= 0 ? set.team : i
        ..aiLevel = set.aiLevel;
      if (set.aiLevel >= 0) {
        p.aiGatherBonus = defs.ai.difficulties[set.aiLevel].gatherBonusPercent;
      }
      p.stock.add(defs.clans[p.clan].startBonus);
      p.rebuildStats(defs);
    }
    final b = w.spawnBuilding(
      tc,
      i,
      s.x - tc.width ~/ 2,
      s.y - tc.height ~/ 2,
      complete: true,
    );
    for (var v = 0; v < defs.balance.startingVillagers; v++) {
      final spot = freeSpawnTile(w, b, -1, -1);
      if (spot == null) break;
      w.spawnUnit(
        villager,
        i,
        Fx.tileCenter(spot.x),
        Fx.tileCenter(spot.y),
      );
    }
    p.popUsed = w.unitsOf(i).length;
  }
  w.victoryMode = victoryMode;
  updateVision(w);
  w.recount();
  return w;
}
