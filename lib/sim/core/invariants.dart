import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Invariants de simulation (Analyse §13.2). Renvoie la liste des violations
/// (vide si l'état est sain). Exécuté après chaque tick en debug/tests.
List<String> checkInvariants(World w) {
  final out = <String>[];
  void fail(String msg) {
    if (out.length < 20) out.add('[tick ${w.tick}] $msg');
  }

  final m = w.map;

  // 1. Ressources ≥ 0 ; 2. population ≥ 0.
  for (final p in w.players) {
    for (final r in Res.values) {
      if (p.stock[r] < 0) fail('Ressource négative joueur ${p.id} ${r.name}');
    }
    if (p.popUsed < 0) fail('Population négative joueur ${p.id}');
    if (p.drum < 0 || p.drum > w.balance.combat.drumMax) {
      fail('Énergie du tambour hors bornes joueur ${p.id} (${p.drum})');
    }
    for (final c in p.spellCd) {
      if (c < 0) fail('Recharge de sort négative joueur ${p.id}');
    }
  }
  if (w.projectiles.length > w.balance.combat.maxProjectiles) {
    fail('Trop de projectiles (${w.projectiles.length})');
  }
  final heroes = <int, int>{};
  for (final u in w.units.values) {
    if (u.alive && u.def.isHero) {
      heroes[u.owner] = (heroes[u.owner] ?? 0) + 1;
    }
    if (w.players[u.owner].defeated && u.alive) {
      fail('Unité ${u.id} d’un joueur éliminé');
    }
  }
  heroes.forEach((owner, n) {
    if (n > 1) fail('Joueur $owner : $n héros vivants (maximum 1)');
  });
  for (final b in w.buildings.values) {
    if (w.players[b.owner].defeated) {
      fail('Bâtiment ${b.id} d’un joueur éliminé');
    }
  }

  bool known(int id) => w.exists(id);

  for (final u in w.units.values) {
    // 4. PV > 0 ; une unité morte est retirée avant la fin du tick.
    if (u.state == UnitState.dead) fail('Unité morte non retirée ${u.id}');
    if (u.hp <= 0) fail('Unité ${u.id} avec PV ${u.hp}');
    if (u.hp > u.maxHp) fail('Unité ${u.id} PV > max');
    if (u.effects.length > w.balance.combat.maxEffects) {
      fail('Unité ${u.id} : trop d’effets (${u.effects.length})');
    }
    for (final e in u.effects) {
      if (e.remaining <= 0) fail('Unité ${u.id} : effet expiré non retiré');
    }
    for (final c in u.powerCd) {
      if (c < 0) fail('Unité ${u.id} : recharge négative');
    }
    if (u.state == UnitState.garrisoned) {
      if (!w.buildings.containsKey(u.garrisonIn)) {
        fail('Unité ${u.id} garnisonnée dans un bâtiment absent');
      }
      continue;
    }
    // 3. Pas hors carte, pas sur une case bloquée.
    if (!m.inBounds(u.tileX, u.tileY)) {
      fail('Unité ${u.id} hors carte (${u.x}, ${u.y})');
      continue;
    }
    if (m.blocked(m.index(u.tileX, u.tileY))) {
      fail('Unité ${u.id} sur une case bloquée (${u.tileX}, ${u.tileY})');
    }
    // 5. Références.
    for (final o in u.orders) {
      if (o.hasTargetId && !known(o.a)) {
        fail('Unité ${u.id}: ordre ${o.kind.name} vers ${o.a} inexistant');
      }
    }
    for (final ref in <int>[u.targetId, u.dropOffId, u.followId]) {
      if (ref >= 0 && !known(ref)) {
        fail('Unité ${u.id}: référence $ref pendante');
      }
    }
    // État cohérent avec la file d'ordres.
    if (u.state == UnitState.idle && u.orders.isNotEmpty) {
      fail('Unité ${u.id} inactive avec ordres');
    }
    if (u.state != UnitState.idle && u.orders.isEmpty) {
      fail('Unité ${u.id} ${u.state.name} sans ordre');
    }
    // 7. En déplacement : chemin, demande en cours ou flow field.
    if (u.state == UnitState.moving &&
        !(u.pathPending || u.flowId >= 0 || u.pathIdx < u.path.length)) {
      fail(
        'Unité ${u.id} en déplacement sans chemin '
        '(ordre=${u.order}, flow=${u.flowId}, partiel=${u.pathPartial}, '
        'version=${u.pathVersion}, tuile=(${u.tileX},${u.tileY}))',
      );
    }
    if (u.carryAmt < 0) fail('Unité ${u.id} charge négative');
    if (u.carryAmt > 0 && u.carryRes < 0) {
      fail('Unité ${u.id} charge sans type');
    }
  }

  // Bâtiments : surface exacte (invariant 10), PV, files (invariant 6).
  final expected = <int, int>{};
  for (final b in w.buildings.values) {
    if (b.hp <= 0 || b.hp > b.maxHp) fail('Bâtiment ${b.id} PV ${b.hp}');
    if (b.stock < 0) fail('Bâtiment ${b.id} stock négatif');
    for (var y = b.ty; y < b.ty + b.def.height; y++) {
      for (var x = b.tx; x < b.tx + b.def.width; x++) {
        if (!m.inBounds(x, y)) {
          fail('Bâtiment ${b.id} hors carte');
          continue;
        }
        expected[m.index(x, y)] = b.id;
      }
    }
    if (b.queue.length > w.balance.maxQueue) fail('File trop longue ${b.id}');
    for (final q in b.queue) {
      final cost = q.isAge
          ? w.defs.ages[q.defIndex].cost
          : (q.isTech
                ? w.defs.techs[q.defIndex].cost
                : w.defs.units[q.defIndex].cost);
      final hero = !q.isTech && !q.isAge && w.defs.units[q.defIndex].isHero;
      // Un héros tombé coûte plus cher à ressusciter : coût payé ≥ coût de base.
      if (hero ? !q.paid.covers(cost) : q.paid != cost) {
        fail('Bâtiment ${b.id}: coût payé ≠ coût remboursable');
      }
    }
    for (final id in b.garrisoned) {
      final u = w.units[id];
      if (u == null || u.garrisonIn != b.id) {
        fail('Bâtiment ${b.id}: garnison incohérente ($id)');
      }
    }
    if (b.rallyTarget >= 0 && !known(b.rallyTarget)) {
      fail('Bâtiment ${b.id}: ralliement pendant');
    }
  }
  for (final n in w.nodes.values) {
    if (n.amount <= 0) fail('Ressource ${n.id} épuisée non retirée');
    expected[m.index(n.tx, n.ty)] = n.id;
  }
  for (var i = 0; i < m.size; i++) {
    final occ = m.occupant[i];
    if (occ != (expected[i] ?? 0)) {
      fail('Occupation incohérente case $i : $occ ≠ ${expected[i] ?? 0}');
      break;
    }
  }
  return out;
}

/// Contrôles structurels d'un monde fraîchement chargé (sauvegarde peut-être
/// corrompue ou malveillante mais au CRC valide) : tailles de tableaux,
/// indices de chemin, positions, plus tous les invariants. Une sauvegarde qui
/// échoue ici est refusée au chargement au lieu de planter plus tard.
List<String> validateStructure(World w) {
  final out = <String>[];
  void fail(String m) {
    if (out.length < 20) out.add(m);
  }

  final m = w.map;
  if (m.width < 1 || m.height < 1 || m.width > 1024 || m.height > 1024) {
    fail('Taille de carte invalide ${m.width}×${m.height}');
    return out;
  }
  if (m.terrain.length != m.size || m.elevation.length != m.size) {
    fail('Tableaux de carte de mauvaise taille');
    return out;
  }
  for (var i = 0; i < m.size; i++) {
    if (m.terrain[i] >= w.defs.terrain.length) {
      fail('Terrain inconnu case $i');
      return out;
    }
  }
  if (w.players.isEmpty || w.players.length > 16) {
    fail('Nombre de joueurs invalide');
    return out;
  }
  for (final p in w.players) {
    if (p.explored.length != m.size || p.visible.length != m.size) {
      fail('Brouillard de mauvaise taille (joueur ${p.id})');
      return out;
    }
  }
  for (final u in w.units.values) {
    if (u.owner < 0 || u.owner >= w.players.length) {
      fail('Propriétaire invalide unité ${u.id}');
    }
    for (final t in u.path) {
      if (t < 0 || t >= m.size) {
        fail('Chemin hors carte unité ${u.id}');
        break;
      }
    }
    if (u.pathIdx < 0 || u.pathIdx > u.path.length) {
      fail('pathIdx invalide unité ${u.id}');
    }
    if (u.carryRes >= 5) fail('Type de charge invalide unité ${u.id}');
    if (u.gatherRes >= 5) fail('Type de récolte invalide unité ${u.id}');
    if (u.maxHp < 1 || u.maxHp > u.def.hp * 4) {
      fail('PV maximum aberrants unité ${u.id}');
    }
    if (u.effects.length > 64) fail('Effets aberrants unité ${u.id}');
  }
  for (final b in w.buildings.values) {
    if (b.owner < 0 || b.owner >= w.players.length) {
      fail('Propriétaire invalide bâtiment ${b.id}');
    }
    if (b.tx < 0 ||
        b.ty < 0 ||
        b.tx + b.def.width > m.width ||
        b.ty + b.def.height > m.height) {
      fail('Bâtiment ${b.id} hors carte');
    }
    for (final q in b.queue) {
      final n = q.isAge
          ? w.defs.ages.length
          : (q.isTech ? w.defs.techs.length : w.defs.units.length);
      if (q.defIndex < 0 || q.defIndex >= n) {
        fail('File invalide bâtiment ${b.id}');
      }
    }
  }
  for (final n in w.nodes.values) {
    if (n.tx < 0 || n.ty < 0 || n.tx >= m.width || n.ty >= m.height) {
      fail('Ressource ${n.id} hors carte');
    }
  }
  for (final p in w.players) {
    for (final t in p.techs) {
      if (t < 0 || t >= w.defs.techs.length) {
        fail('Recherche inconnue joueur ${p.id}');
      }
    }
    if (p.age < 0 || p.age >= w.defs.ages.length) {
      fail('Âge invalide joueur ${p.id}');
    }
    if (p.clan >= w.defs.clans.length) fail('Clan invalide joueur ${p.id}');
    if (p.spellCd.length != w.defs.powers.length) {
      fail('Recharges de sorts de mauvaise taille (joueur ${p.id})');
    }
  }
  if (out.isEmpty) out.addAll(checkInvariants(w));
  return out;
}
