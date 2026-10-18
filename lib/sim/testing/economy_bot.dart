import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/construction.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/player.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Joueur « économie seule » scripté (aucune triche : mêmes commandes que
/// l'interface). Sert de test de bout en bout, de démonstration headless et de
/// base à l'IA de la Phase 6.
class EconomyBot {
  EconomyBot(this.owner, {this.decisionEvery = 10});

  final int owner;
  final int decisionEvery;

  /// Ratios cibles de villageois par ressource.
  static const Map<Res, int> _weights = <Res, int>{
    Res.food: 4,
    Res.wood: 4,
    Res.stone: 1,
    Res.iron: 1,
    Res.gold: 1,
  };

  static const int maxVillagers = 40;

  /// Villageois déjà engagés par une décision de ce passage (évite qu'un ordre
  /// de récolte écrase l'ordre de construction qui vient d'être émis).
  final Set<int> _claimed = <int>{};

  void update(World w) {
    if (w.tick % decisionEvery != 0) return;
    _claimed.clear();
    final p = w.players[owner];
    final mine = w.unitsOf(owner);
    final villagers = mine.where((u) => u.def.villager).toList();
    final tc = _townCenter(w);
    if (tc == null) return;

    _train(w, tc, villagers.length);
    _research(w);
    _buildHouses(w, p, villagers, tc);
    _assignIdle(w, villagers, tc);
  }

  Building? _townCenter(World w) {
    for (final b in w.buildings.values) {
      if (b.owner == owner && b.def.townCenter && b.complete) return b;
    }
    return null;
  }

  void _train(World w, Building tc, int villagers) {
    final p = w.players[owner];
    final queued = tc.queue.length;
    if (queued >= 2 || villagers + queued >= maxVillagers) return;
    if (p.popUsed + queued >= p.popCap) return;
    w.submit(TrainCmd(owner, tc.id, 'villager'));
  }

  void _research(World w) {
    final p = w.players[owner];
    for (final b in w.buildings.values) {
      if (b.owner != owner || !b.complete || b.queue.isNotEmpty) continue;
      for (final t in b.def.researches) {
        final def = w.defs.tech(t);
        if (!p.hasTech(def.index) && p.stock.covers(def.cost)) {
          w.submit(ResearchCmd(owner, b.id, t));
          return;
        }
      }
    }
  }

  void _buildHouses(World w, Player p, List<Unit> villagers, Building tc) {
    final hasBuilding = w.buildings.values.any(
      (b) => b.owner == owner && !b.complete && b.def.popBonus > 0,
    );
    if (hasBuilding || villagers.isEmpty) return;
    final room = p.popCap - p.popUsed - tc.queue.length;
    if (room > 3) return;
    final hut = w.defs.building('hut');
    if (!p.stock.covers(hut.cost)) return;
    final builder = _pickBuilder(villagers);
    if (builder == null) return;
    _place(w, hut, builder, tc.tx, tc.ty);
  }

  Unit? _pickBuilder(List<Unit> villagers) {
    for (final u in villagers) {
      if (u.isIdle) return u;
    }
    for (final u in villagers) {
      if (u.state == UnitState.gathering) return u;
    }
    return null;
  }

  bool _place(World w, BuildingDef def, Unit builder, int nearX, int nearY) {
    for (var r = 2; r < 14; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx.abs() != r && dy.abs() != r) continue;
          final x = nearX + dx;
          final y = nearY + dy;
          if (validatePlacement(w, owner, def, x, y) == CmdResult.ok) {
            w.submit(BuildCmd(owner, [builder.id], def.id, x, y));
            _claimed.add(builder.id);
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Ressource la moins pourvue par rapport aux ratios cibles.
  Res _neediest(List<Unit> villagers) {
    final counts = <Res, int>{for (final r in Res.values) r: 0};
    for (final u in villagers) {
      final r = u.gatherRes;
      if (r >= 0 && u.state == UnitState.gathering) {
        counts[Res.values[r]] = counts[Res.values[r]]! + 1;
      }
    }
    var best = Res.food;
    var bestScore = 1 << 30;
    for (final r in Res.values) {
      final score = counts[r]! * 100 ~/ _weights[r]!;
      if (score < bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return best;
  }

  void _assignIdle(World w, List<Unit> villagers, Building tc) {
    for (final u in villagers) {
      if (!u.isIdle || _claimed.contains(u.id)) continue;
      // Une charge sans dépôt : construire le dépôt manquant près de la source.
      final res = u.carryAmt > 0 ? u.carryType! : _neediest(villagers);
      final target = _nearestSource(w, res, tc, u);
      if (target == null) continue;
      // Le bâtisseur d'un dépôt le construit d'abord (puis récolte seul).
      if (_ensureDropOff(w, res, target, u)) continue;
      w.submit(GatherCmd(owner, [u.id], target.id));
    }
  }

  ({int id, int x, int y})? _nearestSource(
    World w,
    Res res,
    Building tc,
    Unit u,
  ) {
    ({int id, int x, int y})? best;
    var bestD = 1 << 60;
    final cx = tc.tx + 2;
    final cy = tc.ty + 2;
    for (final n in w.nodes.values) {
      if (n.res != res) continue;
      final dx = n.tx - cx;
      final dy = n.ty - cy;
      final d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        best = (id: n.id, x: n.tx, y: n.ty);
      }
    }
    // Nourriture : des champs une fois les baies lointaines.
    if (res == Res.food) {
      for (final b in w.buildings.values) {
        if (b.owner != owner || !b.isField || !b.complete || b.stock <= 0) {
          continue;
        }
        final dx = b.tx - cx;
        final dy = b.ty - cy;
        final d = dx * dx + dy * dy;
        if (d < bestD && gatherersOnField(w, b.id) < w.balance.fieldGatherers) {
          bestD = d;
          best = (id: b.id, x: b.tx, y: b.ty);
        }
      }
      if (best == null || bestD > 12 * 12) {
        final field = w.defs.building('field');
        if (w.players[owner].stock.covers(field.cost) &&
            _place(w, field, u, tc.tx, tc.ty)) {
          return null; // le bâtisseur cultivera le champ une fois fini
        }
      }
    }
    return best;
  }

  int gatherersOnField(World w, int id) => w.units.values
      .where((u) => u.targetId == id && u.state == UnitState.gathering)
      .length;

  /// Construit un dépôt à proximité d'une source trop éloignée d'un dépôt.
  bool _ensureDropOff(World w, Res res, ({int id, int x, int y}) src, Unit u) {
    final near = w.buildings.values.any((b) {
      if (b.owner != owner || !b.def.dropOff.contains(res)) return false;
      final d = World.distToRect(
        Fx.tileCenter(src.x),
        Fx.tileCenter(src.y),
        b.tx,
        b.ty,
        b.def.width,
        b.def.height,
      );
      return d <= 8 * Fx.one;
    });
    if (near) return false;
    final campId = res == Res.wood
        ? 'lumber_camp'
        : (res == Res.food ? 'granary' : 'mining_camp');
    final def = w.defs.building(campId);
    final building = w.buildings.values.any(
      (b) => b.owner == owner && !b.complete && b.def.id == campId,
    );
    if (building || !w.players[owner].stock.covers(def.cost)) return false;
    return _place(w, def, u, src.x, src.y);
  }
}
