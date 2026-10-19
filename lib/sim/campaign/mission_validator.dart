import 'package:age_of_empire_camer/sim/campaign/mission_def.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_runtime.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_setup.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Vérifie la campagne contre les définitions de jeu et la carte générée :
/// références (unités, bâtiments, étiquettes, objectifs, drapeaux), positions
/// praticables et accessibles, ressources suffisantes, objectifs réalisables.
/// Renvoie la liste des problèmes (vide : campagne valide).
List<String> validateCampaign(Defs defs, CampaignDef campaign) {
  final out = <String>[];
  for (final m in campaign.missions) {
    out.addAll(_validateMission(defs, m));
  }
  // Chaînage des missions.
  for (final m in campaign.missions) {
    for (final r in m.requires) {
      if (campaign.byId(r) == null) {
        out.add('${m.id}: mission requise inconnue « $r »');
      }
    }
  }
  return out;
}

List<String> _validateMission(Defs defs, MissionDef m) {
  final out = <String>[];
  void bad(String msg) => out.add('${m.id}: $msg');

  bool hasUnit(String id) => defs.units.any((u) => u.id == id);
  bool hasBuilding(String id) => defs.buildings.any((b) => b.id == id);
  bool hasTech(String id) => defs.techs.any((t) => t.id == id);

  // Joueurs.
  for (final (i, p) in m.players.indexed) {
    if (!defs.clans.any((c) => c.id == p.clan)) {
      bad('joueur $i : clan inconnu « ${p.clan} »');
    }
    if (p.age < 0 || p.age >= defs.ages.length) bad('joueur $i : âge invalide');
    for (final u in p.lockedUnits) {
      if (!hasUnit(u)) bad('joueur $i : unité verrouillée inconnue « $u »');
    }
    for (final b in p.lockedBuildings) {
      if (!hasBuilding(b)) {
        bad('joueur $i : bâtiment verrouillé inconnu « $b »');
      }
    }
    for (final t in p.lockedTechs) {
      if (!hasTech(t)) bad('joueur $i : recherche verrouillée inconnue « $t »');
    }
  }
  for (final id in m.rewardUnits) {
    if (!hasUnit(id)) bad('récompense : unité inconnue « $id »');
  }
  for (final id in m.rewardBuildings) {
    if (!hasBuilding(id)) bad('récompense : bâtiment inconnu « $id »');
  }
  for (final id in m.rewardTechs) {
    if (!hasTech(id)) bad('récompense : recherche inconnue « $id »');
  }

  // Étiquettes produites, drapeaux posés, objectifs révélés.
  final tagsMade = <String>{};
  final flagsSet = <String>{};
  final revealed = <String>{};
  final triggerIds = <String>{};
  final objectiveIds = <String>{};
  for (final o in m.objectives) {
    if (!objectiveIds.add(o.id)) bad('objectif en double « ${o.id} »');
  }
  for (final p in m.placements) {
    if (p.owner < 0 || p.owner >= m.players.length) {
      bad('placement : joueur ${p.owner} inexistant');
    }
    if (p.unit != null && !hasUnit(p.unit!)) {
      bad('placement : unité inconnue « ${p.unit} »');
    }
    if (p.building != null && !hasBuilding(p.building!)) {
      bad('placement : bâtiment inconnu « ${p.building} »');
    }
    if (p.tag != null) tagsMade.add(p.tag!);
  }
  final endingIds = m.endings.map((e) => e.id).toSet();
  for (final t in m.triggers) {
    if (!triggerIds.add(t.id)) bad('déclencheur en double « ${t.id} »');
    for (final a in t.actions) {
      switch (a.kind) {
        case 'spawn':
          final u = a.str('unit') ?? '';
          if (!hasUnit(u)) bad('${t.id} : unité inconnue « $u »');
          if (a.integer('owner', 1) >= m.players.length) {
            bad('${t.id} : joueur inexistant');
          }
          final tag = a.str('tag');
          if (tag != null) tagsMade.add(tag);
        case 'building':
          final b = a.str('building') ?? '';
          if (!hasBuilding(b)) bad('${t.id} : bâtiment inconnu « $b »');
          final tag = a.str('tag');
          if (tag != null) tagsMade.add(tag);
        case 'flag':
          flagsSet.add(a.str('name') ?? '');
        case 'objective':
          revealed.add(a.str('id') ?? '');
        case 'win':
          final e = a.str('ending');
          if (e != null && e.isNotEmpty && !endingIds.contains(e)) {
            bad('${t.id} : fin inconnue « $e »');
          }
      }
    }
  }
  for (final id in revealed) {
    final o = m.objective(id);
    if (o == null) {
      bad('une action révèle un objectif inconnu « $id »');
    } else if (!o.hidden) {
      bad('l’objectif « $id » est révélé mais pas masqué');
    }
  }
  for (final o in m.objectives) {
    if (o.hidden && !revealed.contains(o.id) && !o.optional) {
      bad('objectif obligatoire « ${o.id} » masqué et jamais révélé');
    }
  }

  // Conditions.
  void checkCond(String where, Cond c) {
    final unit = c.str('unit');
    if (unit != null && !hasUnit(unit)) {
      bad('$where : unité inconnue « $unit »');
    }
    final building = c.str('building');
    if (building != null && !hasBuilding(building)) {
      bad('$where : bâtiment inconnu « $building »');
    }
    final owner = c.args['owner'];
    if (owner is int && (owner < 0 || owner >= m.players.length)) {
      bad('$where : joueur $owner inexistant');
    }
    final tag = c.str('tag');
    if (tag != null && !tagsMade.contains(tag)) {
      bad('$where : étiquette « $tag » jamais créée');
    }
    switch (c.kind) {
      case 'objective':
        if (!objectiveIds.contains(c.str('id'))) {
          bad('$where : objectif inconnu « ${c.str('id')} »');
        }
      case 'after_trigger':
        if (!triggerIds.contains(c.str('id'))) {
          bad('$where : déclencheur inconnu « ${c.str('id')} »');
        }
      case 'flag':
        if (!flagsSet.contains(c.str('name'))) {
          bad('$where : drapeau « ${c.str('name')} » jamais posé');
        }
      case 'research':
        if (!hasTech(c.str('tech') ?? '')) bad('$where : recherche inconnue');
      case 'age':
        if (c.integer('age') >= defs.ages.length) {
          bad('$where : âge inexistant');
        }
      case 'gather':
        if (!Res.values.any((r) => r.name == c.str('res'))) {
          bad('$where : ressource inconnue « ${c.str('res')} »');
        }
      case 'tick':
        if (c.integer('seconds') < 0) bad('$where : durée négative');
    }
    for (final k in c.children) {
      checkCond(where, k);
    }
  }

  for (final o in m.objectives) {
    checkCond('objectif ${o.id}', o.done);
    if (o.fail != null) checkCond('objectif ${o.id} (échec)', o.fail!);
  }
  for (final t in m.triggers) {
    checkCond('déclencheur ${t.id}', t.when);
    for (final a in t.actions) {
      final tag = a.str('tag');
      if (a.kind == 'move' && (tag == null || !tagsMade.contains(tag))) {
        bad('${t.id} : déplacement d’une étiquette inexistante « $tag »');
      }
      if (a.kind == 'dialog') {
        final lines = a.args['lines'];
        if (lines is! List<dynamic> || lines.isEmpty) {
          bad('${t.id} : dialogue vide');
        }
      }
    }
  }
  for (final (i, c) in m.lose.indexed) {
    checkCond('défaite $i', c);
  }
  for (final e in m.endings) {
    if (e.when != null) checkCond('fin ${e.id}', e.when!);
  }
  if (m.objectives.every((o) => o.optional) &&
      !m.triggers.any((t) => t.actions.any((a) => a.kind == 'win'))) {
    bad(
      'aucun objectif obligatoire et aucune action « win » : mission interminable',
    );
  }

  // Carte : positions, accessibilité, ressources.
  if (out.isEmpty) {
    final World w;
    try {
      w = createMissionGame(defs, m);
    } on Object catch (e) {
      bad('création de la partie impossible : $e');
      return out;
    }
    out.addAll(_validateMap(defs, m, w));
  }
  return out;
}

List<String> _validateMap(Defs defs, MissionDef m, World w) {
  final out = <String>[];
  void bad(String msg) => out.add('${m.id}: $msg');
  final map = w.map;

  // Accessibilité à pied depuis le joueur 0 (terrain seul).
  final seen = List<bool>.filled(map.size, false);
  final q = <int>[];
  void seed(int x, int y) {
    if (!map.inBounds(x, y)) return;
    final i = map.index(x, y);
    if (seen[i] || !map.terrainDef(i).walkable) return;
    seen[i] = true;
    q.add(i);
  }

  final p0 = w.players.first;
  seed(p0.startX, p0.startY);
  for (var h = 0; h < q.length; h++) {
    final i = q[h];
    final x = i % map.width;
    final y = i ~/ map.width;
    seed(x + 1, y);
    seed(x - 1, y);
    seed(x, y + 1);
    seed(x, y - 1);
  }
  bool reachable(int x, int y) {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (map.inBounds(x + dx, y + dy) && seen[map.index(x + dx, y + dy)]) {
          return true;
        }
      }
    }
    return false;
  }

  void checkPos(String where, PosDef pos) {
    final (x, y) = resolvePos(w, pos);
    if (!map.terrainDef(map.index(x, y)).walkable) {
      // Le moteur cherche la case libre la plus proche : seul un trou de carte
      // sans aucune case praticable à proximité est un vrai problème.
      if (freeTileNear(w, x, y, <int>{}) == null) {
        bad('$where : aucune case praticable près de ($x, $y)');
        return;
      }
    }
    final near = freeTileNear(w, x, y, <int>{});
    if (near != null && !reachable(near.$1, near.$2)) {
      bad('$where : ($x, $y) inaccessible à pied depuis le joueur 0');
    }
  }

  for (final (i, p) in m.placements.indexed) {
    checkPos('placement $i', p.at);
  }
  for (final t in m.triggers) {
    for (final a in t.actions) {
      if (a.args['at'] != null) {
        checkPos('${t.id}/${a.kind}', _posArg(a.args['at']));
      }
      if (a.args['to'] != null) {
        checkPos('${t.id}/${a.kind}.to', _posArg(a.args['to']));
      }
    }
  }

  // Ressources suffisantes pour les objectifs de récolte.
  final available = <Res, int>{for (final r in Res.values) r: 0};
  for (final n in w.nodes.values) {
    available[n.res] = available[n.res]! + n.amount;
  }
  void walk(Cond c) {
    if (c.kind == 'gather' && c.integer('owner') == 0) {
      final r = Res.values.firstWhere((r) => r.name == c.str('res'));
      // Les champs renouvelables fournissent la nourriture sans limite.
      if (r != Res.food && c.integer('amount') > available[r]!) {
        bad(
          'récolte de ${c.integer('amount')} ${r.name} : seulement ${available[r]} sur la carte',
        );
      }
    }
    c.children.forEach(walk);
  }

  for (final o in m.objectives) {
    walk(o.done);
  }

  // Objectifs de construction / production impossibles car verrouillés.
  final locked = <String>{
    ...m.players.first.lockedUnits,
    ...m.players.first.lockedBuildings,
    ...m.players.first.lockedTechs,
  };
  void need(String where, Cond c) {
    if ((c.kind == 'build' || c.kind == 'units') && c.integer('owner') == 0) {
      final id = c.str('building') ?? c.str('unit');
      if (id != null && locked.contains(id) && !_unlockedByTrigger(m, id)) {
        bad('$where : « $id » est verrouillé et ne sera jamais débloqué');
      }
    }
    for (final k in c.children) {
      need(where, k);
    }
  }

  for (final o in m.objectives) {
    if (!o.optional) need('objectif ${o.id}', o.done);
  }
  return out;
}

/// Les verrous ne bougent qu'avec les récompenses de missions précédentes.
bool _unlockedByTrigger(MissionDef m, String id) => false;

PosDef _posArg(Object? v) {
  if (v is List<dynamic>) return PosDef(null, v[0] as int, v[1] as int);
  final j = v! as Map<String, dynamic>;
  return PosDef(
    j['from'] as String? ?? 'p0',
    (j['dx'] as int?) ?? 0,
    (j['dy'] as int?) ?? 0,
  );
}
