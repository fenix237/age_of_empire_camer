import 'dart:math' as math;

import 'package:age_of_empire_camer/sim/campaign/mission_def.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/core/hashing.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/unit_system.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// États d'un objectif.
abstract final class ObjState {
  static const int hidden = 0;
  static const int active = 1;
  static const int done = 2;
  static const int failed = 3;
}

/// État de la mission.
abstract final class MissionStatus {
  static const int running = 0;
  static const int won = 1;
  static const int lost = 2;
}

/// Équipe « gagnante » d'une mission perdue (ni le joueur ni égalité).
const int missionLostTeam = -3;

/// Réplique de dialogue affichée par l'interface.
class DialogLine {
  const DialogLine(this.speaker, this.text);

  final String speaker;
  final String text;
}

/// Moteur de mission : évalue objectifs, déclencheurs et conditions de
/// défaite à intervalle fixe, de façon déterministe (il fait partie de la
/// simulation : état sauvegardé et haché, rejoué à l'identique).
class MissionRuntime {
  MissionRuntime(this.def, {this.difficulty = 1}) {
    for (final o in def.objectives) {
      objectives[o.id] = o.hidden ? ObjState.hidden : ObjState.active;
    }
  }

  final MissionDef def;

  /// 0 facile, 1 normal, 2 difficile.
  final int difficulty;

  final Map<String, int> objectives = <String, int>{};

  /// Déclencheur → tick de son déclenchement.
  final Map<String, int> fired = <String, int>{};
  final Set<String> flags = <String>{};

  /// Entités marquées (unités ou bâtiments) par étiquette.
  final Map<String, List<int>> tags = <String, List<int>>{};

  int status = MissionStatus.running;
  String ending = '';
  String endingText = '';
  String loseReason = '';
  int stars = 0;
  int endTick = -1;

  /// Bandeau d'aide courant (tutoriel).
  String hint = '';

  /// Dialogues en attente d'affichage. Transitoire côté rendu : l'interface
  /// les consomme, la simulation n'en dépend pas.
  final List<List<DialogLine>> dialogs = <List<DialogLine>>[];

  bool get running => status == MissionStatus.running;
  bool get won => status == MissionStatus.won;

  MissionDifficulty get diff =>
      def.difficulties[difficulty.clamp(0, def.difficulties.length - 1)];

  int objectiveState(String id) => objectives[id] ?? ObjState.hidden;

  /// Objectifs visibles dans l'ordre de la définition.
  List<ObjectiveDef> get visibleObjectives => <ObjectiveDef>[
    for (final o in def.objectives)
      if (objectiveState(o.id) != ObjState.hidden) o,
  ];

  // ───────────────────────── Boucle ─────────────────────────

  void update(World w) {
    if (!running || w.tick % 5 != 0) return;
    _objectives(w);
    for (final t in def.triggers) {
      if (fired.containsKey(t.id)) continue;
      if (!_eval(w, t.when)) continue;
      fired[t.id] = w.tick;
      for (final a in t.actions) {
        _act(w, a);
        if (!running) return;
      }
    }
    _objectives(w);
    for (final c in def.lose) {
      if (_eval(w, c)) {
        _finish(w, won: false, reason: 'lose');
        return;
      }
    }
    var mandatory = 0;
    var finished = 0;
    for (final o in def.objectives) {
      if (o.optional) continue;
      mandatory++;
      final st = objectiveState(o.id);
      if (st == ObjState.failed) {
        _finish(w, won: false, reason: o.id);
        return;
      }
      if (st == ObjState.done) finished++;
    }
    if (mandatory > 0 && finished == mandatory) _finish(w, won: true);
  }

  void _objectives(World w) {
    for (final o in def.objectives) {
      if (objectiveState(o.id) != ObjState.active) continue;
      if (_eval(w, o.done)) {
        objectives[o.id] = ObjState.done;
      } else if (o.fail != null && _eval(w, o.fail!)) {
        objectives[o.id] = ObjState.failed;
      }
    }
  }

  void _finish(
    World w, {
    required bool won,
    String ending = '',
    String reason = '',
  }) {
    if (!running) return;
    status = won ? MissionStatus.won : MissionStatus.lost;
    endTick = w.tick;
    loseReason = reason;
    w
      ..gameOver = true
      ..winnerTeam = won ? w.players.first.team : missionLostTeam;
    if (!won) return;
    var chosen = ending.isEmpty ? null : ending;
    var text = '';
    for (final e in def.endings) {
      if (chosen != null
          ? e.id == chosen
          : (e.when == null || _eval(w, e.when!))) {
        chosen = e.id;
        text = e.text;
        break;
      }
    }
    this.ending = chosen ?? '';
    endingText = text;
    stars = _stars(w);
  }

  int _stars(World w) {
    var s = 1;
    if (w.tick ~/ 10 <= def.starSeconds) s++;
    final optionals = def.objectives.where((o) => o.optional);
    final allOptional = optionals.every(
      (o) => objectiveState(o.id) == ObjState.done,
    );
    if (allOptional && w.players.first.stats.unitsLost <= def.starMaxLosses) {
      s++;
    }
    return s;
  }

  // ───────────────────────── Conditions ─────────────────────────

  bool _eval(World w, Cond c) {
    switch (c.kind) {
      case 'always':
        return true;
      case 'tick':
        return w.tick >= c.integer('seconds') * 10;
      case 'objective':
        return objectiveState(c.str('id') ?? '') == ObjState.done;
      case 'build':
        final owner = c.integer('owner');
        final id = c.str('building');
        var n = 0;
        for (final b in w.buildings.values) {
          if (b.owner == owner &&
              b.complete &&
              (id == null || b.def.id == id)) {
            n++;
          }
        }
        return n >= c.integer('count', 1);
      case 'units':
        final owner = c.integer('owner');
        final id = c.str('unit');
        final cls = c.str('class');
        var n = 0;
        for (final u in w.units.values) {
          if (u.owner != owner || !u.alive) continue;
          if (id != null && u.def.id != id) continue;
          if (cls != null && !u.def.classes.contains(cls)) continue;
          n++;
        }
        return n >= c.integer('count', 1);
      case 'gather':
        final r = Res.values.firstWhere((r) => r.name == c.str('res'));
        return w.players[c.integer('owner')].stats.gathered[r.index] >=
            c.integer('amount');
      case 'age':
        return w.players[c.integer('owner')].age >= c.integer('age');
      case 'research':
        return w.players[c.integer('owner')].hasTech(
          w.defs.tech(c.str('tech') ?? '').index,
        );
      case 'killed':
        return w.players[c.integer('owner')].stats.unitsKilled >=
            c.integer('count');
      case 'no_buildings':
        return !_anyBuilding(w, c);
      case 'no_units':
        return !_anyUnit(w, c);
      case 'tag_alive':
        return _aliveTagged(w, c.str('tag') ?? '') >= c.integer('atLeast', 1);
      case 'unit_in_area':
        return _unitInArea(w, c);
      case 'flag':
        return flags.contains(c.str('name'));
      case 'after_trigger':
        final at = fired[c.str('id') ?? ''];
        return at != null && w.tick - at >= c.integer('seconds') * 10;
      case 'all':
        return c.children.every((e) => _eval(w, e));
      case 'any':
        return c.children.any((e) => _eval(w, e));
      case 'not':
        return !_eval(w, c.children.first);
    }
    return false;
  }

  bool _anyBuilding(World w, Cond c) {
    final owner = c.integer('owner', 1);
    final id = c.str('building');
    final tag = c.str('tag');
    final tagged = tag == null ? null : (tags[tag] ?? const <int>[]).toSet();
    for (final b in w.buildings.values) {
      if (b.owner != owner) continue;
      if (id != null && b.def.id != id) continue;
      if (tagged != null && !tagged.contains(b.id)) continue;
      return true;
    }
    return false;
  }

  bool _anyUnit(World w, Cond c) {
    final owner = c.integer('owner', 1);
    final id = c.str('unit');
    final tag = c.str('tag');
    final cls = c.str('class');
    final tagged = tag == null ? null : (tags[tag] ?? const <int>[]).toSet();
    for (final u in w.units.values) {
      if (!u.alive || u.owner != owner) continue;
      if (id != null && u.def.id != id) continue;
      if (cls != null && !u.def.classes.contains(cls)) continue;
      if (tagged != null && !tagged.contains(u.id)) continue;
      return true;
    }
    return false;
  }

  int _aliveTagged(World w, String tag) {
    var n = 0;
    for (final id in tags[tag] ?? const <int>[]) {
      final u = w.units[id];
      if ((u != null && u.alive) || w.buildings.containsKey(id)) n++;
    }
    return n;
  }

  bool _unitInArea(World w, Cond c) {
    final owner = c.integer('owner');
    final id = c.str('unit');
    final tag = c.str('tag');
    final (cx, cy) = resolvePos(w, _posOf(c.args['at']));
    final r = c.integer('radius', 3);
    final tagged = tag == null ? null : (tags[tag] ?? const <int>[]).toSet();
    for (final u in w.units.values) {
      if (!u.alive || u.owner != owner) continue;
      if (id != null && u.def.id != id) continue;
      if (tagged != null && !tagged.contains(u.id)) continue;
      final dx = u.tileX - cx;
      final dy = u.tileY - cy;
      if (dx * dx + dy * dy <= r * r) return true;
    }
    return false;
  }

  // ───────────────────────── Actions ─────────────────────────

  void _act(World w, ActionDef a) {
    switch (a.kind) {
      case 'dialog':
        final lines = <DialogLine>[
          for (final l in a.args['lines'] as List<dynamic>)
            DialogLine(
              (l as Map<String, dynamic>)['speaker'] as String? ?? '',
              l['text'] as String? ?? '',
            ),
        ];
        if (lines.isNotEmpty) dialogs.add(lines);
      case 'hint':
        hint = a.str('text') ?? '';
      case 'objective':
        final id = a.str('id') ?? '';
        if (objectiveState(id) == ObjState.hidden &&
            objectives.containsKey(id)) {
          objectives[id] = ObjState.active;
        }
      case 'flag':
        flags.add(a.str('name') ?? '');
      case 'give':
        final p = w.players[a.integer('owner')];
        final res =
            a.args['resources'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        for (final r in Res.values) {
          final v = res[r.name];
          if (v is int) p.stock[r] += v;
        }
      case 'reveal':
        _reveal(w, a);
      case 'ai':
        final p = w.players[a.integer('owner', 1)];
        p.aiLevel = a.integer('level', -1);
        p.aiGatherBonus = p.aiLevel >= 0
            ? w
                  .defs
                  .ai
                  .difficulties[p.aiLevel.clamp(
                    0,
                    w.defs.ai.difficulties.length - 1,
                  )]
                  .gatherBonusPercent
            : 0;
      case 'spawn':
        _spawn(w, a);
      case 'building':
        _placeBuilding(w, a);
      case 'move':
        final (x, y) = resolvePos(w, _posOf(a.args['at']));
        final us = <Unit>[
          for (final id in tags[a.str('tag') ?? ''] ?? const <int>[])
            if (w.units[id] != null && w.units[id]!.alive) w.units[id]!,
        ];
        if (us.isNotEmpty) issueGroupMove(w, us, x, y, queue: false);
      case 'win':
        _finish(w, won: true, ending: a.str('ending') ?? '');
      case 'lose':
        _finish(w, won: false, reason: a.str('reason') ?? 'lose');
    }
  }

  void _reveal(World w, ActionDef a) {
    final p = w.players[a.integer('owner')];
    final (cx, cy) = resolvePos(w, _posOf(a.args['at']));
    final r = a.integer('radius', 8);
    final m = w.map;
    for (var y = cy - r; y <= cy + r; y++) {
      for (var x = cx - r; x <= cx + r; x++) {
        if (!m.inBounds(x, y)) continue;
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
          p.explored[m.index(x, y)] = 1;
        }
      }
    }
    w.visionRevision++;
  }

  void _spawn(World w, ActionDef a) {
    final owner = a.integer('owner', 1);
    final def = w.defs.unit(a.str('unit') ?? '');
    var count = a.integer('count', 1);
    final scaled = (a.args['scale'] as bool?) ?? owner != 0;
    if (scaled) count = math.max(1, (count * diff.enemyPct + 50) ~/ 100);
    final (cx, cy) = resolvePos(w, _posOf(a.args['at']));
    final made = <Unit>[];
    final used = <int>{};
    for (var i = 0; i < count; i++) {
      final spot = freeTileNear(w, cx, cy, used);
      if (spot == null) break;
      used.add(w.map.index(spot.$1, spot.$2));
      made.add(
        w.spawnUnit(def, owner, Fx.tileCenter(spot.$1), Fx.tileCenter(spot.$2)),
      );
    }
    final tag = a.str('tag');
    if (tag != null) {
      (tags[tag] ??= <int>[]).addAll(made.map((u) => u.id));
    }
    final to = a.args['to'];
    if (to != null && made.isNotEmpty) {
      final (x, y) = resolvePos(w, _posOf(to));
      issueGroupMove(w, made, x, y, queue: false);
    }
  }

  void _placeBuilding(World w, ActionDef a) {
    final owner = a.integer('owner', 1);
    final def = w.defs.building(a.str('building') ?? '');
    final (cx, cy) = resolvePos(w, _posOf(a.args['at']));
    final b = placeBuildingNear(
      w,
      owner,
      def,
      cx,
      cy,
      complete: (a.args['complete'] as bool?) ?? true,
    );
    final tag = a.str('tag');
    if (tag != null && b != null) (tags[tag] ??= <int>[]).add(b.id);
  }

  // ───────────────────────── Sérialisation ─────────────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': def.id,
    'difficulty': difficulty,
    'status': status,
    'ending': ending,
    'endingText': endingText,
    'reason': loseReason,
    'stars': stars,
    'endTick': endTick,
    'hint': hint,
    'obj': objectives,
    'fired': fired,
    'flags': flags.toList()..sort(),
    'tags': tags,
    'dialogs': <dynamic>[
      for (final d in dialogs)
        <dynamic>[
          for (final l in d) <String, String>{'s': l.speaker, 't': l.text},
        ],
    ],
  };

  static MissionRuntime restore(MissionDef def, Map<String, dynamic> j) {
    final r = MissionRuntime(def, difficulty: j['difficulty'] as int)
      ..status = j['status'] as int
      ..ending = j['ending'] as String
      ..endingText = (j['endingText'] as String?) ?? ''
      ..loseReason = (j['reason'] as String?) ?? ''
      ..stars = j['stars'] as int
      ..endTick = j['endTick'] as int
      ..hint = j['hint'] as String;
    (j['obj'] as Map<String, dynamic>).forEach(
      (k, v) => r.objectives[k] = v as int,
    );
    (j['fired'] as Map<String, dynamic>).forEach(
      (k, v) => r.fired[k] = v as int,
    );
    r.flags.addAll(List<String>.from(j['flags'] as List<dynamic>));
    (j['tags'] as Map<String, dynamic>).forEach(
      (k, v) => r.tags[k] = List<int>.from(v as List<dynamic>),
    );
    for (final d in j['dialogs'] as List<dynamic>) {
      r.dialogs.add(<DialogLine>[
        for (final l in d as List<dynamic>)
          DialogLine(
            (l as Map<String, dynamic>)['s'] as String,
            l['t'] as String,
          ),
      ]);
    }
    return r;
  }

  /// Ajoute l'état de la mission au hash d'état (hors dialogues et aide).
  void hashInto(StateHasher h) {
    h
      ..addInt(status)
      ..addInt(difficulty)
      ..addInt(stars)
      ..addInt(endTick);
    for (final id in objectives.keys.toList()..sort()) {
      h
        ..addInt(stableStringHash(id))
        ..addInt(objectives[id]!);
    }
    for (final id in fired.keys.toList()..sort()) {
      h
        ..addInt(stableStringHash(id))
        ..addInt(fired[id]!);
    }
    for (final f in flags.toList()..sort()) {
      h.addInt(stableStringHash(f));
    }
    for (final t in tags.keys.toList()..sort()) {
      h
        ..addInt(stableStringHash(t))
        ..addInts(tags[t]!);
    }
  }
}

// ───────────────────────── Utilitaires de placement ─────────────────────────

PosDef _posOf(Object? v) {
  if (v is List<dynamic>) return PosDef(null, v[0] as int, v[1] as int);
  final m = v! as Map<String, dynamic>;
  return PosDef(
    m['from'] as String? ?? 'p0',
    (m['dx'] as int?) ?? 0,
    (m['dy'] as int?) ?? 0,
  );
}

/// Résout une position en case de carte (bornée).
(int, int) resolvePos(World w, PosDef p) {
  var bx = 0;
  var by = 0;
  final from = p.from;
  if (from == 'center') {
    bx = w.map.width ~/ 2;
    by = w.map.height ~/ 2;
  } else if (from != null && from.startsWith('p')) {
    final i = int.tryParse(from.substring(1)) ?? 0;
    final pl = w.players[i.clamp(0, w.players.length - 1)];
    bx = pl.startX;
    by = pl.startY;
  }
  return (
    (bx + p.dx).clamp(1, w.map.width - 2),
    (by + p.dy).clamp(1, w.map.height - 2),
  );
}

/// Case libre et praticable la plus proche de (x, y), hors [used].
(int, int)? freeTileNear(World w, int x, int y, Set<int> used) {
  final m = w.map;
  for (var r = 0; r <= 14; r++) {
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        if (dx.abs() != r && dy.abs() != r) continue;
        final tx = x + dx;
        final ty = y + dy;
        if (!m.inBounds(tx, ty)) continue;
        final i = m.index(tx, ty);
        if (m.blocked(i) || used.contains(i)) continue;
        return (tx, ty);
      }
    }
  }
  return null;
}

/// Pose un bâtiment sur l'emplacement valide le plus proche de (x, y).
Building? placeBuildingNear(
  World w,
  int owner,
  BuildingDef def,
  int x,
  int y, {
  required bool complete,
}) {
  for (var r = 0; r <= 14; r++) {
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        if (dx.abs() != r && dy.abs() != r) continue;
        final tx = x + dx - def.width ~/ 2;
        final ty = y + dy - def.height ~/ 2;
        if (!w.map.inBounds(tx, ty)) continue;
        if (!_footprintFree(w, def, tx, ty)) continue;
        return w.spawnBuilding(def, owner, tx, ty, complete: complete);
      }
    }
  }
  return null;
}

bool _footprintFree(World w, BuildingDef def, int tx, int ty) {
  final m = w.map;
  for (var y = ty; y < ty + def.height; y++) {
    for (var x = tx; x < tx + def.width; x++) {
      if (!m.inBounds(x, y) || m.blocked(m.index(x, y))) return false;
    }
  }
  return true;
}
