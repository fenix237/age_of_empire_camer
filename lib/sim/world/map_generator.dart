import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/core/rng.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/world/game_map.dart';

/// Ressource à poser sur la carte générée.
class NodeSpawn {
  const NodeSpawn(this.defId, this.x, this.y);

  final String defId;
  final int x;
  final int y;
}

class GeneratedMap {
  const GeneratedMap({
    required this.map,
    required this.starts,
    required this.nodes,
    required this.seedUsed,
    required this.attempts,
  });

  final GameMap map;

  /// Centre de chaque joueur (case).
  final List<({int x, int y})> starts;
  final List<NodeSpawn> nodes;

  /// Graine effectivement utilisée (peut différer après régénération).
  final int seedUsed;
  final int attempts;
}

/// Taille de l'emprise du centre-ville au départ (cases).
const int startTownCenterSize = 4;

/// Générateur procédural déterministe, avec validation de connexité.
abstract final class MapGenerator {
  static GeneratedMap generate(
    Defs defs, {
    required int seed,
    required int size,
    required int players,
    int style = 0,
  }) {
    if (size < 32 || size > 256) {
      throw ArgumentError.value(size, 'size', 'entre 32 et 256');
    }
    if (players < 1 || players > 8) {
      throw ArgumentError.value(players, 'players', 'entre 1 et 8');
    }
    final cfg = defs.balance.mapGen;
    var s = seed;
    for (var attempt = 1; attempt <= cfg.maxAttempts; attempt++) {
      final g = _build(
        defs,
        s,
        size,
        players,
        attempt,
        bridge: false,
        style: style,
      );
      if (g != null) return g;
      s++;
    }
    // Dernier recours : ponts garantis entre les bases.
    return _build(
      defs,
      s,
      size,
      players,
      cfg.maxAttempts + 1,
      bridge: true,
      style: style,
    )!;
  }

  // ── Bruit de valeur entier ──

  static int _lattice(int x, int y, int seed) {
    var h = x * 374761393 + y * 668265263 + seed * 1274126177;
    h = (h ^ (h >>> 13)) * 1274126177;
    h = h ^ (h >>> 16);
    return h & 0xFF;
  }

  static int _noise(int x, int y, int scale, int seed) {
    final gx = x ~/ scale;
    final gy = y ~/ scale;
    final fx = (x % scale) * 256 ~/ scale;
    final fy = (y % scale) * 256 ~/ scale;
    int smooth(int t) => (t * t * (768 - 2 * t)) >> 16; // 3t²-2t³ (0..256)
    final sx = smooth(fx);
    final sy = smooth(fy);
    final a = _lattice(gx, gy, seed);
    final b = _lattice(gx + 1, gy, seed);
    final c = _lattice(gx, gy + 1, seed);
    final d = _lattice(gx + 1, gy + 1, seed);
    final top = a * (256 - sx) + b * sx;
    final bot = c * (256 - sx) + d * sx;
    return (top * (256 - sy) + bot * sy) >> 16;
  }

  static int _terrainIndex(Defs defs, String id) =>
      defs.terrain.firstWhere((t) => t.id == id).index;

  static GeneratedMap? _build(
    Defs defs,
    int seed,
    int size,
    int players,
    int attempt, {
    required bool bridge,
    int style = 0,
  }) {
    final styles = defs.balance.mapStyles;
    final cfg = defs.balance.mapGen.withStyle(
      styles[style.clamp(0, styles.length - 1)],
    );
    final rng = Rng(seed);
    final map = GameMap(size, size, defs.terrain);
    final tGrass = _terrainIndex(defs, 'grass');
    final tDirt = _terrainIndex(defs, 'dirt');
    final tSand = _terrainIndex(defs, 'sand');
    final tSavanna = _terrainIndex(defs, 'savanna');
    final tShallow = _terrainIndex(defs, 'shallow');
    final tDeep = _terrainIndex(defs, 'deep');
    final tMountain = _terrainIndex(defs, 'mountain');
    final tRoad = _terrainIndex(defs, 'road');

    final nSeed = seed & 0x7FFFFFFF;
    final moist = Uint8List(size * size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        final e =
            (_noise(x, y, cfg.noiseScale, nSeed) * 2 +
                _noise(x, y, cfg.noiseScale ~/ 2 + 1, nSeed + 7)) ~/
            3;
        moist[i] =
            (_noise(x, y, cfg.noiseScale ~/ 2 + 2, nSeed + 99) * 2 +
                _noise(x, y, cfg.noiseScale, nSeed + 31)) ~/
            3;
        int t;
        if (e < cfg.deepWaterLevel) {
          t = tDeep;
        } else if (e < cfg.waterLevel) {
          t = tShallow;
        } else if (e > cfg.mountainLevel) {
          t = tMountain;
        } else if (e < cfg.waterLevel + 8) {
          t = tSand;
        } else if (moist[i] < 80) {
          t = tSavanna;
        } else if (moist[i] > 200) {
          t = tDirt;
        } else {
          t = tGrass;
        }
        map.terrain[i] = t;
        map.elevation[i] = e > 190 ? 2 : (e > 150 ? 1 : 0);
      }
    }

    // Positions de départ : anneau autour du centre, réparties équitablement.
    final center = size ~/ 2;
    final ringR = (size ~/ 2) * cfg.playerRingPercent ~/ 100;
    final offset = rng.nextInt(360);
    final starts = <({int x, int y})>[];
    for (var i = 0; i < players; i++) {
      final ang = offset + i * 360 ~/ players;
      var sx = center + ((ringR * Fx.cosQ16(ang)) >> 16);
      var sy = center + ((ringR * Fx.sinQ16(ang)) >> 16);
      final margin = cfg.baseClearRadius + 2;
      sx = sx.clamp(margin, size - margin - 1);
      sy = sy.clamp(margin, size - margin - 1);
      starts.add((x: sx, y: sy));
    }

    // Dégagement des bases (terre ferme herbeuse, plate).
    final clear = cfg.baseClearRadius;
    for (final s in starts) {
      for (var y = s.y - clear; y <= s.y + clear; y++) {
        for (var x = s.x - clear; x <= s.x + clear; x++) {
          if (!map.inBounds(x, y)) continue;
          final dx = x - s.x;
          final dy = y - s.y;
          if (dx * dx + dy * dy <= clear * clear) {
            map.terrain[map.index(x, y)] = tGrass;
            map.elevation[map.index(x, y)] = 0;
          }
        }
      }
    }

    if (bridge) {
      for (var i = 1; i < starts.length; i++) {
        _carve(map, starts[i - 1], starts[i], tRoad);
      }
    }

    // Bâtiments de départ : emprise du centre-ville (bloquée pour le BFS).
    final blockedMask = Uint8List(size * size);
    for (final s in starts) {
      for (var y = s.y - 2; y < s.y + 2; y++) {
        for (var x = s.x - 2; x < s.x + 2; x++) {
          blockedMask[map.index(x, y)] = 1;
        }
      }
    }

    final nodes = <NodeSpawn>[];
    final occupied = Uint8List.fromList(blockedMask);
    bool free(int x, int y) {
      if (!map.inBounds(x, y)) return false;
      final i = map.index(x, y);
      if (occupied[i] != 0 || !map.terrainWalkable(i)) return false;
      return map.terrain[i] != tShallow;
    }

    bool awayFromStarts(int x, int y, int r) {
      for (final s in starts) {
        final dx = x - s.x;
        final dy = y - s.y;
        if (dx * dx + dy * dy < r * r) return false;
      }
      return true;
    }

    final clusters = <List<NodeSpawn>>[];
    void put(String id, int x, int y) {
      occupied[map.index(x, y)] = 1;
      nodes.add(NodeSpawn(id, x, y));
    }

    // Place un groupe de [count] ressources autour d'un point tiré dans
    // l'anneau [minR, maxR] autour de [s]. Renvoie le nombre posé.
    int cluster(
      ({int x, int y}) s,
      String id,
      int count,
      int minR,
      int maxR, {
      int spread = 2,
    }) {
      for (var tries = 0; tries < 40; tries++) {
        final ang = rng.nextInt(360);
        final r = rng.range(minR, maxR);
        final cx = s.x + ((r * Fx.cosQ16(ang)) >> 16);
        final cy = s.y + ((r * Fx.sinQ16(ang)) >> 16);
        var placed = 0;
        var x = cx;
        var y = cy;
        for (var step = 0; step < count * 12 && placed < count; step++) {
          if (free(x, y) && awayFromStarts(x, y, 5)) {
            put(id, x, y);
            placed++;
          }
          x = cx + rng.range(-spread - (placed ~/ 6), spread + (placed ~/ 6));
          y = cy + rng.range(-spread - (placed ~/ 6), spread + (placed ~/ 6));
        }
        if (placed >= count) {
          clusters.add(nodes.sublist(nodes.length - placed));
          return placed;
        }
        // Cluster incomplet : on l'annule et on retente ailleurs.
        for (var k = 0; k < placed; k++) {
          final n = nodes.removeLast();
          occupied[map.index(n.x, n.y)] = 0;
        }
      }
      return 0;
    }

    final guaranteed = <String, int>{};
    void need(String id, int n) => guaranteed[id] = (guaranteed[id] ?? 0) + n;

    for (final s in starts) {
      for (var f = 0; f < cfg.startForests; f++) {
        cluster(s, 'tree', cfg.treesPerStartForest, 8, 13, spread: 3);
        need('tree', cfg.treesPerStartForest);
      }
      cluster(s, 'berries', cfg.startBerries, 6, 9);
      need('berries', cfg.startBerries);
      cluster(s, 'quarry', cfg.startStone, 9, 14);
      need('quarry', cfg.startStone);
      cluster(s, 'iron_mine', cfg.startIron, 9, 14);
      need('iron_mine', cfg.startIron);
      cluster(s, 'gold_mine', cfg.startGold, 10, 15);
      need('gold_mine', cfg.startGold);
      cluster(s, 'game', cfg.startGame, 11, 16, spread: 4);
      need('game', cfg.startGame);
    }

    // Forêts et ressources éparses (bruit).
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        if (!free(x, y) || !awayFromStarts(x, y, clear + 1)) continue;
        final t = map.terrain[i];
        if (t == tSand || t == tRoad) continue;
        if (moist[i] > cfg.forestThreshold && rng.nextInt(100) < 65) {
          put('tree', x, y);
        } else if (rng.nextInt(1000) < cfg.scatterPerThousand) {
          put('tree', x, y);
        }
      }
    }

    // ── Validation ──
    final counts = <String, int>{};
    for (final n in nodes) {
      counts[n.defId] = (counts[n.defId] ?? 0) + 1;
    }
    for (final e in guaranteed.entries) {
      if ((counts[e.key] ?? 0) < e.value) return null;
    }
    if (!_connected(map, starts, clusters, blockedMask)) return null;

    return GeneratedMap(
      map: map,
      starts: starts,
      nodes: nodes,
      seedUsed: seed,
      attempts: attempt,
    );
  }

  /// Creuse un couloir en L entre deux bases.
  static void _carve(
    GameMap map,
    ({int x, int y}) a,
    ({int x, int y}) b,
    int t,
  ) {
    var x = a.x;
    var y = a.y;
    while (x != b.x) {
      map.terrain[map.index(x, y)] = t;
      x += x < b.x ? 1 : -1;
    }
    while (y != b.y) {
      map.terrain[map.index(x, y)] = t;
      y += y < b.y ? 1 : -1;
    }
    map.terrain[map.index(x, y)] = t;
  }

  /// Toutes les bases et chaque ressource sont atteignables depuis la base 0.
  static bool _connected(
    GameMap map,
    List<({int x, int y})> starts,
    List<List<NodeSpawn>> clusters,
    Uint8List blockedMask,
  ) {
    final w = map.width;
    final blocked = Uint8List.fromList(blockedMask);
    for (final c in clusters) {
      for (final n in c) {
        blocked[map.index(n.x, n.y)] = 1;
      }
    }
    bool open(int x, int y) {
      if (!map.inBounds(x, y)) return false;
      final i = map.index(x, y);
      return blocked[i] == 0 && map.terrainWalkable(i);
    }

    final door = (x: starts[0].x - 3, y: starts[0].y);
    if (!open(door.x, door.y)) return false;
    final seen = Uint8List(map.size);
    final queue = <int>[map.index(door.x, door.y)];
    seen[queue.first] = 1;
    for (var head = 0; head < queue.length; head++) {
      final c = queue[head];
      final cx = c % w;
      final cy = c ~/ w;
      for (var d = 0; d < 4; d++) {
        final nx =
            cx +
            (d == 0
                ? 1
                : d == 1
                ? -1
                : 0);
        final ny =
            cy +
            (d == 2
                ? 1
                : d == 3
                ? -1
                : 0);
        if (!open(nx, ny)) continue;
        final ni = ny * w + nx;
        if (seen[ni] != 0) continue;
        seen[ni] = 1;
        queue.add(ni);
      }
    }
    for (final s in starts) {
      final i = map.index(s.x - 3, s.y);
      if (!open(s.x - 3, s.y) || seen[i] == 0) return false;
    }
    // Chaque groupe garanti doit avoir au moins un nœud accessible.
    for (final c in clusters) {
      var ok = false;
      for (final n in c) {
        for (var dy = -1; dy <= 1 && !ok; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final x = n.x + dx;
            final y = n.y + dy;
            if ((dx != 0 || dy != 0) &&
                map.inBounds(x, y) &&
                seen[map.index(x, y)] != 0) {
              ok = true;
              break;
            }
          }
        }
        if (ok) break;
      }
      if (!ok) return false;
    }
    return true;
  }
}
