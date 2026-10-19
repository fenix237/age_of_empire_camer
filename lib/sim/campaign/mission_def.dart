import 'dart:convert';

import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';

/// Définitions de la campagne (Phase 7) : données pures chargées depuis
/// `assets/campaign/campaign.json`. Le moteur (`mission_runtime.dart`) les
/// interprète ; `mission_validator.dart` les vérifie contre les définitions
/// de jeu et la carte générée.

/// Position sur la carte : absolue `[x, y]` ou relative à un point d'ancrage
/// (`p0`, `p1`… départ d'un joueur, `center`) avec décalage.
class PosDef {
  const PosDef(this.from, this.dx, this.dy);

  /// null : coordonnées absolues.
  final String? from;
  final int dx;
  final int dy;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (from != null) 'from': from,
    'dx': dx,
    'dy': dy,
  };
}

/// Condition booléenne composable (objectifs, déclencheurs, défaites).
class Cond {
  const Cond(this.kind, this.args, [this.children = const <Cond>[]]);

  final String kind;
  final Map<String, dynamic> args;

  /// Sous-conditions de `all`, `any`, `not`.
  final List<Cond> children;

  String? str(String k) => args[k] as String?;
  int integer(String k, [int d = 0]) => (args[k] as int?) ?? d;
}

class ObjectiveDef {
  const ObjectiveDef({
    required this.id,
    required this.label,
    required this.done,
    this.fail,
    this.optional = false,
    this.hidden = false,
  });

  final String id;
  final String label;
  final Cond done;

  /// Condition d'échec de l'objectif (un objectif obligatoire raté perd la
  /// mission).
  final Cond? fail;
  final bool optional;

  /// Invisible jusqu'à l'action `objective` d'un déclencheur.
  final bool hidden;
}

class ActionDef {
  const ActionDef(this.kind, this.args);

  final String kind;
  final Map<String, dynamic> args;

  String? str(String k) => args[k] as String?;
  int integer(String k, [int d = 0]) => (args[k] as int?) ?? d;
}

class TriggerDef {
  const TriggerDef({
    required this.id,
    required this.when,
    required this.actions,
  });

  final String id;
  final Cond when;
  final List<ActionDef> actions;
}

/// Entité posée au début de la mission (garde, village, base ennemie…).
class PlacementDef {
  const PlacementDef({
    required this.owner,
    required this.at,
    this.unit,
    this.building,
    this.count = 1,
    this.tag,
    this.complete = true,
  });

  final int owner;
  final String? unit;
  final String? building;
  final int count;
  final PosDef at;
  final String? tag;
  final bool complete;
}

class MissionPlayerDef {
  const MissionPlayerDef({
    required this.clan,
    required this.ai,
    required this.team,
    required this.base,
    required this.age,
    this.resources,
    this.lockedUnits = const <String>[],
    this.lockedBuildings = const <String>[],
    this.lockedTechs = const <String>[],
  });

  final String clan;

  /// -1 : humain (joueur 0) ou adversaire scripté sans IA ; sinon difficulté
  /// de base de l'IA (modulée par la difficulté de la mission).
  final int ai;
  final int team;

  /// Centre-ville et villageois de départ (faux : joueur sans base).
  final bool base;
  final int age;
  final Stock? resources;
  final List<String> lockedUnits;
  final List<String> lockedBuildings;
  final List<String> lockedTechs;
}

class MissionDifficulty {
  const MissionDifficulty({
    required this.aiLevel,
    required this.enemyPct,
    required this.resourcePct,
  });

  /// Ajout au niveau d'IA de base (-1, 0, +1).
  final int aiLevel;

  /// Pourcentage appliqué aux effectifs des vagues ennemies.
  final int enemyPct;

  /// Pourcentage appliqué aux ressources de départ du joueur.
  final int resourcePct;
}

class EndingDef {
  const EndingDef({required this.id, required this.when, required this.text});

  final String id;
  final Cond? when;
  final String text;
}

class MissionDef {
  const MissionDef({
    required this.id,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.briefing,
    required this.kingdomX,
    required this.kingdomY,
    required this.mapSize,
    required this.mapSeed,
    required this.mapStyle,
    required this.players,
    required this.placements,
    required this.objectives,
    required this.triggers,
    required this.lose,
    required this.endings,
    required this.difficulties,
    required this.starSeconds,
    required this.starMaxLosses,
    required this.rewardUnits,
    required this.rewardBuildings,
    required this.rewardTechs,
    required this.requires,
  });

  final String id;
  final int index;
  final String title;
  final String subtitle;
  final List<String> briefing;

  /// Position sur la carte du royaume (0–100).
  final double kingdomX;
  final double kingdomY;

  final int mapSize;
  final int mapSeed;
  final int mapStyle;
  final List<MissionPlayerDef> players;
  final List<PlacementDef> placements;
  final List<ObjectiveDef> objectives;
  final List<TriggerDef> triggers;
  final List<Cond> lose;
  final List<EndingDef> endings;

  /// Trois niveaux : facile, normal, difficile.
  final List<MissionDifficulty> difficulties;

  /// Étoile de performance : durée maximale et pertes maximales.
  final int starSeconds;
  final int starMaxLosses;

  /// Déblocages accordés à la victoire.
  final List<String> rewardUnits;
  final List<String> rewardBuildings;
  final List<String> rewardTechs;

  /// Missions à terminer avant celle-ci (en plus de l'ordre).
  final List<String> requires;

  ObjectiveDef? objective(String id) {
    for (final o in objectives) {
      if (o.id == id) return o;
    }
    return null;
  }

  List<String> get rewards => <String>[
    ...rewardUnits,
    ...rewardBuildings,
    ...rewardTechs,
  ];
}

class CampaignDef {
  const CampaignDef(this.missions);

  final List<MissionDef> missions;

  MissionDef? byId(String id) {
    for (final m in missions) {
      if (m.id == id) return m;
    }
    return null;
  }

  static CampaignDef fromString(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw DataException('campaign', '', 'JSON illisible : ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw DataException('campaign', '', "l'objet racine est attendu");
    }
    return fromJson(decoded);
  }

  static CampaignDef fromJson(Map<String, dynamic> root) {
    final list = _list(root, 'missions', r'$');
    final missions = <MissionDef>[];
    for (var i = 0; i < list.length; i++) {
      missions.add(_mission(_obj(list[i], '\$.missions[$i]'), i));
    }
    final ids = <String>{};
    for (final m in missions) {
      if (!ids.add(m.id)) {
        throw DataException('campaign', m.id, 'identifiant en double');
      }
    }
    if (missions.isEmpty) {
      throw DataException('campaign', r'$.missions', 'au moins une mission');
    }
    return CampaignDef(missions);
  }
}

// ───────────────────────── Lecture typée ─────────────────────────

Never _bad(String path, String msg) =>
    throw DataException('campaign', path, msg);

Map<String, dynamic> _obj(Object? o, String path) {
  if (o is Map<String, dynamic>) return o;
  _bad(path, 'objet attendu');
}

List<dynamic> _list(Map<String, dynamic> o, String k, String path) {
  final v = o[k];
  if (v == null) _bad('$path.$k', 'liste manquante');
  if (v is! List<dynamic>) _bad('$path.$k', 'liste attendue');
  return v;
}

List<dynamic> _optList(Map<String, dynamic> o, String k) =>
    (o[k] as List<dynamic>?) ?? const <dynamic>[];

String _str(Map<String, dynamic> o, String k, String path) {
  final v = o[k];
  if (v is! String || v.isEmpty) _bad('$path.$k', 'texte attendu');
  return v;
}

int _int(Map<String, dynamic> o, String k, String path, {int? def}) {
  final v = o[k];
  if (v == null && def != null) return def;
  if (v is! int) _bad('$path.$k', 'entier attendu');
  return v;
}

List<String> _strs(Map<String, dynamic> o, String k, String path) {
  final l = _optList(o, k);
  return <String>[
    for (var i = 0; i < l.length; i++)
      l[i] is String ? l[i] as String : _bad('$path.$k[$i]', 'texte attendu'),
  ];
}

PosDef _pos(Object? v, String path) {
  if (v is List<dynamic> && v.length == 2 && v[0] is int && v[1] is int) {
    return PosDef(null, v[0] as int, v[1] as int);
  }
  if (v is Map<String, dynamic>) {
    return PosDef(
      v['from'] as String? ?? 'p0',
      (v['dx'] as int?) ?? 0,
      (v['dy'] as int?) ?? 0,
    );
  }
  _bad(path, 'position attendue : [x, y] ou {"from", "dx", "dy"}');
}

const Set<String> _condKinds = <String>{
  'tick',
  'objective',
  'build',
  'units',
  'gather',
  'age',
  'research',
  'killed',
  'no_buildings',
  'no_units',
  'tag_alive',
  'unit_in_area',
  'flag',
  'after_trigger',
  'all',
  'any',
  'not',
  'always',
};

Cond _cond(Object? v, String path) {
  final o = _obj(v, path);
  final kind = _str(o, 'kind', path);
  if (!_condKinds.contains(kind)) {
    _bad('$path.kind', 'condition inconnue « $kind »');
  }
  final children = <Cond>[];
  if (kind == 'all' || kind == 'any') {
    final l = _list(o, 'conds', path);
    for (var i = 0; i < l.length; i++) {
      children.add(_cond(l[i], '$path.conds[$i]'));
    }
    if (children.isEmpty) _bad('$path.conds', 'au moins une sous-condition');
  } else if (kind == 'not') {
    children.add(_cond(o['cond'], '$path.cond'));
  }
  return Cond(kind, Map<String, dynamic>.of(o), children);
}

const Set<String> _actionKinds = <String>{
  'dialog',
  'hint',
  'objective',
  'spawn',
  'building',
  'give',
  'flag',
  'reveal',
  'ai',
  'move',
  'win',
  'lose',
};

ActionDef _action(Object? v, String path) {
  final o = _obj(v, path);
  final kind = _str(o, 'kind', path);
  if (!_actionKinds.contains(kind)) {
    _bad('$path.kind', 'action inconnue « $kind »');
  }
  return ActionDef(kind, Map<String, dynamic>.of(o));
}

Stock? _stock(Object? v, String path) {
  if (v == null) return null;
  final o = _obj(v, path);
  final s = Stock();
  for (final r in Res.values) {
    final x = o[r.name];
    if (x == null) continue;
    if (x is! int || x < 0) _bad('$path.${r.name}', 'entier positif attendu');
    s[r] = x;
  }
  for (final k in o.keys) {
    if (!Res.values.any((r) => r.name == k)) {
      _bad('$path.$k', 'ressource inconnue');
    }
  }
  return s;
}

MissionDef _mission(Map<String, dynamic> o, int index) {
  final path = '\$.missions[$index]';
  final id = _str(o, 'id', path);
  final map = _obj(o['map'], '$path.map');
  final size = _int(map, 'size', '$path.map');
  if (size < 32 || size > 160) _bad('$path.map.size', 'taille entre 32 et 160');

  final players = <MissionPlayerDef>[];
  final pl = _list(o, 'players', path);
  if (pl.isEmpty) _bad('$path.players', 'au moins le joueur humain');
  for (var i = 0; i < pl.length; i++) {
    final p = _obj(pl[i], '$path.players[$i]');
    final locked = p['locked'] == null
        ? const <String, dynamic>{}
        : _obj(p['locked'], '$path.players[$i].locked');
    players.add(
      MissionPlayerDef(
        clan: _str(p, 'clan', '$path.players[$i]'),
        ai: _int(p, 'ai', '$path.players[$i]', def: -1),
        team: _int(p, 'team', '$path.players[$i]', def: i),
        base: (p['base'] as bool?) ?? true,
        age: _int(p, 'age', '$path.players[$i]', def: 0),
        resources: _stock(p['resources'], '$path.players[$i].resources'),
        lockedUnits: _strs(locked, 'units', '$path.players[$i].locked'),
        lockedBuildings: _strs(locked, 'buildings', '$path.players[$i].locked'),
        lockedTechs: _strs(locked, 'techs', '$path.players[$i].locked'),
      ),
    );
  }
  if (players.first.ai != -1) {
    _bad('$path.players[0].ai', 'le joueur 0 est le joueur humain (ai = -1)');
  }

  final placements = <PlacementDef>[];
  final pls = _optList(o, 'placements');
  for (var i = 0; i < pls.length; i++) {
    final p = _obj(pls[i], '$path.placements[$i]');
    final unit = p['unit'] as String?;
    final building = p['building'] as String?;
    if ((unit == null) == (building == null)) {
      _bad('$path.placements[$i]', 'exactement un de « unit » ou « building »');
    }
    placements.add(
      PlacementDef(
        owner: _int(p, 'owner', '$path.placements[$i]'),
        unit: unit,
        building: building,
        count: _int(p, 'count', '$path.placements[$i]', def: 1),
        at: _pos(p['at'], '$path.placements[$i].at'),
        tag: p['tag'] as String?,
        complete: (p['complete'] as bool?) ?? true,
      ),
    );
  }

  final objectives = <ObjectiveDef>[];
  final obs = _list(o, 'objectives', path);
  for (var i = 0; i < obs.length; i++) {
    final b = _obj(obs[i], '$path.objectives[$i]');
    objectives.add(
      ObjectiveDef(
        id: _str(b, 'id', '$path.objectives[$i]'),
        label: _str(b, 'label', '$path.objectives[$i]'),
        done: _cond(b['done'], '$path.objectives[$i].done'),
        fail: b['fail'] == null
            ? null
            : _cond(b['fail'], '$path.objectives[$i].fail'),
        optional: (b['optional'] as bool?) ?? false,
        hidden: (b['hidden'] as bool?) ?? false,
      ),
    );
  }
  if (objectives.isEmpty) _bad('$path.objectives', 'au moins un objectif');

  final triggers = <TriggerDef>[];
  final trs = _optList(o, 'triggers');
  for (var i = 0; i < trs.length; i++) {
    final t = _obj(trs[i], '$path.triggers[$i]');
    final acts = _list(t, 'do', '$path.triggers[$i]');
    triggers.add(
      TriggerDef(
        id: _str(t, 'id', '$path.triggers[$i]'),
        when: _cond(t['when'], '$path.triggers[$i].when'),
        actions: <ActionDef>[
          for (var k = 0; k < acts.length; k++)
            _action(acts[k], '$path.triggers[$i].do[$k]'),
        ],
      ),
    );
  }

  final lose = <Cond>[
    for (final (i, c) in _optList(o, 'lose').indexed)
      _cond(c, '$path.lose[$i]'),
  ];

  final endings = <EndingDef>[];
  final ens = _optList(o, 'endings');
  for (var i = 0; i < ens.length; i++) {
    final e = _obj(ens[i], '$path.endings[$i]');
    endings.add(
      EndingDef(
        id: _str(e, 'id', '$path.endings[$i]'),
        when: e['when'] == null
            ? null
            : _cond(e['when'], '$path.endings[$i].when'),
        text: _str(e, 'text', '$path.endings[$i]'),
      ),
    );
  }

  final diffs = <MissionDifficulty>[];
  final dj = o['difficulty'] == null
      ? const <String, dynamic>{}
      : _obj(o['difficulty'], '$path.difficulty');
  const defaults = <(String, int, int, int)>[
    ('easy', -1, 70, 130),
    ('normal', 0, 100, 100),
    ('hard', 1, 140, 80),
  ];
  for (final (name, ai, enemy, res) in defaults) {
    final d = dj[name] == null
        ? const <String, dynamic>{}
        : _obj(dj[name], '$path.difficulty.$name');
    diffs.add(
      MissionDifficulty(
        aiLevel: _int(d, 'aiLevel', '$path.difficulty.$name', def: ai),
        enemyPct: _int(d, 'enemyPct', '$path.difficulty.$name', def: enemy),
        resourcePct: _int(d, 'resourcePct', '$path.difficulty.$name', def: res),
      ),
    );
  }

  final stars = o['stars'] == null
      ? const <String, dynamic>{}
      : _obj(o['stars'], '$path.stars');
  final rewards = o['rewards'] == null
      ? const <String, dynamic>{}
      : _obj(o['rewards'], '$path.rewards');
  final kingdom = o['kingdom'] as List<dynamic>?;

  return MissionDef(
    id: id,
    index: index,
    title: _str(o, 'title', path),
    subtitle: (o['subtitle'] as String?) ?? '',
    briefing: _strs(o, 'briefing', path),
    kingdomX: kingdom == null
        ? 10.0 + index * 12
        : (kingdom[0] as num).toDouble(),
    kingdomY: kingdom == null ? 50.0 : (kingdom[1] as num).toDouble(),
    mapSize: size,
    mapSeed: _int(map, 'seed', '$path.map', def: 1),
    mapStyle: _int(map, 'style', '$path.map', def: 0),
    players: players,
    placements: placements,
    objectives: objectives,
    triggers: triggers,
    lose: lose,
    endings: endings,
    difficulties: diffs,
    starSeconds: _int(stars, 'seconds', '$path.stars', def: 1 << 30),
    starMaxLosses: _int(stars, 'maxLosses', '$path.stars', def: 1 << 30),
    rewardUnits: _strs(rewards, 'units', '$path.rewards'),
    rewardBuildings: _strs(rewards, 'buildings', '$path.rewards'),
    rewardTechs: _strs(rewards, 'techs', '$path.rewards'),
    requires: _strs(o, 'requires', path),
  );
}
