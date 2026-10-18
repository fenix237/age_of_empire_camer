import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Recalcule la visibilité (par joueur) à partir des entités ; la case vue est
/// marquée « explorée » de façon permanente (brouillard de guerre à 3 états :
/// inconnu / exploré / visible).
///
/// Avec `mergeExplored: false` (chargement d'une sauvegarde) seule la
/// visibilité courante est recalculée : l'ensemble « exploré » fait partie de
/// l'état sauvegardé et doit évoluer exactement comme sans interruption.
void updateVision(World w, {bool mergeExplored = true}) {
  w.visionRevision++;
  for (final p in w.players) {
    p.visible.fillRange(0, p.visible.length, 0);
  }
  for (final u in w.units.values) {
    if (!u.alive || u.state == UnitState.garrisoned) continue;
    _stamp(w, u.owner, u.tileX, u.tileY, u.def.vision);
  }
  for (final b in w.buildings.values) {
    final r = b.complete ? b.def.vision : 2;
    _stamp(
      w,
      b.owner,
      b.tx + b.def.width ~/ 2,
      b.ty + b.def.height ~/ 2,
      r + (b.def.width > b.def.height ? b.def.width : b.def.height) ~/ 2,
    );
  }
  if (!mergeExplored) return;
  for (final p in w.players) {
    for (var i = 0; i < p.visible.length; i++) {
      if (p.visible[i] != 0) p.explored[i] = 1;
    }
  }
}

void _stamp(World w, int owner, int cx, int cy, int radius) {
  final m = w.map;
  final vis = w.players[owner].visible;
  final r2 = radius * radius;
  for (var y = cy - radius; y <= cy + radius; y++) {
    if (y < 0 || y >= m.height) continue;
    final dy = y - cy;
    for (var x = cx - radius; x <= cx + radius; x++) {
      if (x < 0 || x >= m.width) continue;
      final dx = x - cx;
      if (dx * dx + dy * dy <= r2) vis[y * m.width + x] = 1;
    }
  }
}
