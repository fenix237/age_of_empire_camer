import 'dart:ui';

import 'package:age_of_empire_camer/game/camera.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Ce qui se trouve sous le pointeur.
enum PickKind { none, unit, building, resource }

class PickResult {
  const PickResult(this.kind, this.id, this.tileX, this.tileY);

  static const PickResult none = PickResult(PickKind.none, -1, 0, 0);

  final PickKind kind;
  final int id;
  final int tileX;
  final int tileY;

  bool get isNone => kind == PickKind.none;
}

/// Décalage vertical (px monde) du « corps » d'une unité au-dessus de ses pieds.
const double unitBodyLift = 18 * 1.7;

/// Position écran du corps d'une unité (cible de clic).
Offset unitScreenPos(GameCamera cam, Unit u) {
  final w = Iso.fromFixed(u.x, u.y);
  return cam.worldToScreen(w.translate(0, -unitBodyLift));
}

/// Désigne l'entité sous un point d'écran.
///
/// - Priorité : unité > bâtiment > ressource.
/// - [tolerance] (px écran) agrandit la zone de clic : au toucher, le doigt
///   cache la cible, on choisit la plus proche dans un rayon de 28 dp.
/// - [buildingNeighbors] étend cette tolérance aux bâtiments des cases
///   voisines ; à désactiver quand on donne un ordre (sinon un appui sur le sol
///   près du centre-ville serait pris pour un ordre « garnison »).
PickResult pickAt(
  World w,
  GameCamera cam,
  Offset screen, {
  double tolerance = 22,
  int? preferOwner,
  bool buildingNeighbors = true,
}) {
  Unit? best;
  var bestD = tolerance * tolerance;
  for (final u in w.units.values) {
    if (!u.alive || u.state == UnitState.garrisoned) continue;
    final p = unitScreenPos(cam, u);
    final d = (p - screen).distanceSquared;
    final better =
        d < bestD ||
        (d == bestD &&
            best != null &&
            preferOwner != null &&
            u.owner == preferOwner &&
            best.owner != preferOwner);
    if (better) {
      bestD = d;
      best = u;
    }
  }
  if (best != null) {
    return PickResult(PickKind.unit, best.id, best.tileX, best.tileY);
  }
  final t = cam.screenToTile(screen);
  if (!w.map.inBounds(t.x, t.y)) return PickResult.none;
  final occ = w.map.occupant[w.map.index(t.x, t.y)];
  if (occ != 0) {
    if (w.buildings.containsKey(occ)) {
      return PickResult(PickKind.building, occ, t.x, t.y);
    }
    if (w.nodes.containsKey(occ)) {
      return PickResult(PickKind.resource, occ, t.x, t.y);
    }
  }
  // Tolérance tactile pour bâtiments/ressources : cases voisines.
  if (tolerance > 24) {
    for (final off in const <List<int>>[
      [1, 0],
      [0, 1],
      [-1, 0],
      [0, -1],
      [1, 1],
      [-1, -1],
      [1, -1],
      [-1, 1],
    ]) {
      final x = t.x + off[0];
      final y = t.y + off[1];
      if (!w.map.inBounds(x, y)) continue;
      final o = w.map.occupant[w.map.index(x, y)];
      if (o == 0) continue;
      final centre = cam.worldToScreen(Iso.tileCenter(x, y));
      if ((centre - screen).distance > tolerance * 2) continue;
      if (buildingNeighbors && w.buildings.containsKey(o)) {
        return PickResult(PickKind.building, o, x, y);
      }
      if (w.nodes.containsKey(o)) {
        return PickResult(PickKind.resource, o, x, y);
      }
    }
  }
  return PickResult(PickKind.none, -1, t.x, t.y);
}

/// Unités de [owner] dont le corps est dans le rectangle d'écran.
List<int> unitsInScreenRect(World w, GameCamera cam, Rect rect, int owner) {
  final out = <int>[];
  for (final u in w.units.values) {
    if (!u.alive || u.owner != owner || u.state == UnitState.garrisoned) {
      continue;
    }
    if (rect.contains(unitScreenPos(cam, u))) out.add(u.id);
  }
  return out;
}

/// Sélection courante + groupes de contrôle (Ctrl+0-9).
class SelectionModel {
  final List<int> _units = <int>[];
  int _building = -1;
  final Map<int, List<int>> _groups = <int, List<int>>{};
  int _idleCursor = -1;

  List<int> get units => List<int>.unmodifiable(_units);
  int get building => _building;
  bool get isEmpty => _units.isEmpty && _building < 0;
  bool contains(int id) => _units.contains(id) || _building == id;

  void clear() {
    _units.clear();
    _building = -1;
  }

  void selectUnits(Iterable<int> ids, {bool add = false}) {
    if (!add) clear();
    _building = -1;
    for (final id in ids) {
      if (!_units.contains(id)) _units.add(id);
    }
  }

  void toggleUnit(int id) {
    _building = -1;
    if (!_units.remove(id)) _units.add(id);
  }

  void selectBuilding(int id) {
    _units.clear();
    _building = id;
  }

  /// Retire de la sélection ce qui n'existe plus.
  void prune(World w) {
    _units.removeWhere((id) {
      final u = w.units[id];
      return u == null || !u.alive;
    });
    if (_building >= 0 && !w.buildings.containsKey(_building)) _building = -1;
    _groups.forEach(
      (_, ids) => ids.removeWhere((id) => !w.units.containsKey(id)),
    );
  }

  void setGroup(int n) {
    assert(n >= 0 && n <= 9, 'groupe 0..9');
    if (_units.isEmpty) return;
    _groups[n] = List<int>.of(_units);
  }

  /// Rappelle un groupe ; renvoie false s'il est vide ou détruit.
  bool recallGroup(int n, World w) {
    final g = _groups[n];
    if (g == null) return false;
    g.removeWhere((id) => !w.units.containsKey(id));
    if (g.isEmpty) return false;
    selectUnits(g);
    return true;
  }

  List<int> group(int n) => List<int>.unmodifiable(_groups[n] ?? const <int>[]);

  /// Double-clic : toutes les unités de même type visibles à l'écran.
  List<int> sameTypeVisible(World w, GameCamera cam, Unit like) {
    final rect = Offset.zero & cam.viewport;
    return <int>[
      for (final u in w.units.values)
        if (u.alive &&
            u.owner == like.owner &&
            u.def.id == like.def.id &&
            u.state != UnitState.garrisoned &&
            rect.contains(unitScreenPos(cam, u)))
          u.id,
    ];
  }

  /// Touche « villageois inactif » : passe au suivant, cycliquement.
  Unit? nextIdleVillager(World w, int owner) {
    final idle = <Unit>[
      for (final u in w.units.values)
        if (u.alive && u.owner == owner && u.def.villager && u.isIdle) u,
    ];
    if (idle.isEmpty) return null;
    final next = idle.firstWhere(
      (u) => u.id > _idleCursor,
      orElse: () => idle.first,
    );
    _idleCursor = next.id;
    return next;
  }
}
