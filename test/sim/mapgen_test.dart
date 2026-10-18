import 'dart:io';

import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/world/map_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

final bool _full = Platform.environment['SIM_FULL'] == '1';

void main() {
  test('génération déterministe : mêmes paramètres, même carte', () {
    final a = MapGenerator.generate(testDefs, seed: 77, size: 64, players: 2);
    final b = MapGenerator.generate(testDefs, seed: 77, size: 64, players: 2);
    expect(a.map.terrain, b.map.terrain);
    expect(a.map.elevation, b.map.elevation);
    expect(a.starts, b.starts);
    expect(
      a.nodes.map((n) => '${n.defId}@${n.x},${n.y}').toList(),
      b.nodes.map((n) => '${n.defId}@${n.x},${n.y}').toList(),
    );
    final c = MapGenerator.generate(testDefs, seed: 78, size: 64, players: 2);
    expect(c.map.terrain, isNot(a.map.terrain));
  });

  test('paramètres invalides refusés', () {
    expect(
      () => MapGenerator.generate(testDefs, seed: 1, size: 8, players: 2),
      throwsArgumentError,
    );
    expect(
      () => MapGenerator.generate(testDefs, seed: 1, size: 64, players: 0),
      throwsArgumentError,
    );
  });

  test('ressources de départ garanties pour chaque joueur', () {
    final cfg = testDefs.balance.mapGen;
    for (final seed in [1, 2, 3, 4, 5]) {
      final g = MapGenerator.generate(
        testDefs,
        seed: seed,
        size: 64,
        players: 4,
      );
      for (final s in g.starts) {
        int near(String id) => g.nodes
            .where(
              (n) =>
                  n.defId == id &&
                  (n.x - s.x).abs() <= 18 &&
                  (n.y - s.y).abs() <= 18,
            )
            .length;
        expect(near('tree'), greaterThanOrEqualTo(cfg.treesPerStartForest));
        expect(near('berries'), greaterThanOrEqualTo(cfg.startBerries));
        expect(near('quarry'), greaterThanOrEqualTo(cfg.startStone));
        expect(near('iron_mine'), greaterThanOrEqualTo(cfg.startIron));
        expect(near('gold_mine'), greaterThanOrEqualTo(cfg.startGold));
        expect(near('game'), greaterThanOrEqualTo(cfg.startGame));
      }
    }
  });

  test('aucune ressource sur l’emprise d’un centre-ville ni en double', () {
    final g = MapGenerator.generate(testDefs, seed: 11, size: 64, players: 3);
    final seen = <int>{};
    for (final n in g.nodes) {
      expect(seen.add(n.y * 64 + n.x), isTrue, reason: 'doublon ${n.x},${n.y}');
      for (final s in g.starts) {
        final inTc =
            n.x >= s.x - 2 && n.x < s.x + 2 && n.y >= s.y - 2 && n.y < s.y + 2;
        expect(inTc, isFalse);
      }
      expect(g.map.terrainWalkable(g.map.index(n.x, n.y)), isTrue);
    }
  });

  test('createGame : centre-ville, villageois, ressources et vision', () {
    final w = createGame(testDefs, seed: 5);
    expect(w.players.length, 2);
    for (final p in w.players) {
      expect(p.stock.v, testDefs.balance.startingResources.v);
      expect(w.unitsOf(p.id).length, testDefs.balance.startingVillagers);
      expect(
        w.buildings.values
            .where((b) => b.owner == p.id && b.def.townCenter)
            .length,
        1,
      );
      expect(p.explored.any((e) => e != 0), isTrue);
    }
    expect(w.nodes, isNotEmpty);
  });

  test('génération : 500 cartes valides (tailles et joueurs variés)', () {
    var regenerated = 0;
    for (var i = 0; i < 500; i++) {
      final size = 48 + (i % 4) * 16;
      final players = 1 + i % 4;
      final g = MapGenerator.generate(
        testDefs,
        seed: i * 31 + 7,
        size: size,
        players: players,
      );
      if (g.attempts > 1) regenerated++;
      expect(g.starts.length, players);
    }
    expect(regenerated, lessThan(500));
  });

  test(
    'porte de sortie : 10 000 cartes sans carte invalide',
    () {
      final n = _full ? 10000 : 300;
      for (var i = 0; i < n; i++) {
        final size = 40 + (i % 5) * 24;
        final players = 2 + i % 3;
        final g = MapGenerator.generate(
          testDefs,
          seed: i,
          size: size,
          players: players,
        );
        // La validation interne garantit la connexité : on vérifie ici le contrat.
        expect(g.starts.length, players);
        for (final s in g.starts) {
          expect(g.map.terrainWalkable(g.map.index(s.x - 3, s.y)), isTrue);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
