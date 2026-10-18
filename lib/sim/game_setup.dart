import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/systems/production.dart';
import 'package:age_of_empire_camer/sim/systems/vision.dart';
import 'package:age_of_empire_camer/sim/world/map_generator.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Crée une partie prête à jouer : carte générée, ressources, centre-ville
/// et villageois de départ pour chaque joueur.
World createGame(
  Defs defs, {
  required int seed,
  int size = 64,
  int players = 2,
}) {
  final gen = MapGenerator.generate(
    defs,
    seed: seed,
    size: size,
    players: players,
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
      ..stock = defs.balance.startingResources.copy();
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
  updateVision(w);
  w.recount();
  return w;
}
