import 'dart:math' as math;

import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/systems/unit_system.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Rayon d'impact d'un projectile à tête chercheuse (virgule fixe).
const int projectileHitFx = 128;

/// Convertit des millièmes de case en virgule fixe.
int milliToFx(int milli) => milli * Fx.one ~/ 1000;

// ───────────────────────── Relations ─────────────────────────

/// Deux joueurs sont hostiles s'ils ne sont pas dans la même équipe.
bool hostile(World w, int a, int b) => w.players[a].team != w.players[b].team;

// ───────────────────────── Effets ─────────────────────────

int effectSum(Unit u, EffectKind kind) {
  var sum = 0;
  for (final e in u.effects) {
    if (e.kind == kind) sum += e.value;
  }
  return sum;
}

bool hasEffect(Unit u, EffectKind kind) {
  for (final e in u.effects) {
    if (e.kind == kind) return true;
  }
  return false;
}

bool isStunned(Unit u) => hasEffect(u, EffectKind.stun);

/// Immobilisé : étourdi ou enraciné (un enraciné peut encore frapper).
bool isRooted(Unit u) => isStunned(u) || hasEffect(u, EffectKind.root);

/// Pourcentage de vitesse (100 = normal) : recherches, clan, effets, plafonds.
int speedPercentOf(World w, Unit u) {
  final c = w.balance.combat;
  final p = w.players[u.owner];
  final buff = effectSum(u, EffectKind.speed).clamp(0, c.attackBuffCapPercent);
  final slow = effectSum(u, EffectKind.slow).clamp(0, c.slowCapPercent);
  final pct = 100 + p.mod('speed', u.def) + buff - slow;
  return pct < 10 ? 10 : pct;
}

/// Pourcentage d'attaque (100 = normal), sans bonus de hauteur ni premier coup.
int attackPercentOf(World w, Unit u) {
  final c = w.balance.combat;
  final p = w.players[u.owner];
  final fx = effectSum(
    u,
    EffectKind.attackPct,
  ).clamp(-c.attackDebuffCapPercent, c.attackBuffCapPercent);
  final pct = 100 + p.mod('attack', u.def) + fx;
  return pct < 5 ? 5 : pct;
}

int gatherEffectPercent(Unit u) => effectSum(u, EffectKind.gatherPct);

int armorBonusOf(World w, Unit u) {
  final cap = w.balance.combat.armorBuffCap;
  return effectSum(u, EffectKind.armorAdd).clamp(-cap, cap);
}

/// Armure d'une unité contre un type de dégâts.
int unitArmor(World w, Unit t, DamageType type) {
  final p = w.players[t.owner];
  final base = type == DamageType.pierce
      ? t.def.pierceArmor + p.mod('pierce_armor', t.def)
      : t.def.armor + p.mod('armor', t.def);
  final a = base + armorBonusOf(w, t);
  return a < 0 ? 0 : a;
}

/// Armure d'un bâtiment contre un type de dégâts.
int buildingArmor(World w, Building b, DamageType type) {
  final p = w.players[b.owner];
  switch (type) {
    case DamageType.pierce:
      return b.def.effectivePierceArmor + p.buildingMod('pierce_armor');
    case DamageType.melee:
      return b.def.armor + p.buildingMod('armor');
    case DamageType.siege:
      return (b.def.armor + p.buildingMod('armor')) ~/
          w.balance.combat.siegeBuildingArmorDivisor;
  }
}

/// Portée d'attaque en cases (recherches comprises) ; la hauteur est ajoutée
/// séparément.
int rangeTilesOf(World w, Unit u) {
  if (u.def.range == 0) return 0;
  return u.def.range + w.players[u.owner].mod('range', u.def);
}

/// Bonus de hauteur : +1 case de portée à distance, dégâts majorés.
bool higherGround(World w, int ax, int ay, int bx, int by) {
  final m = w.map;
  if (!m.inBounds(ax, ay) || !m.inBounds(bx, by)) return false;
  return m.elevation[m.index(ax, ay)] > m.elevation[m.index(bx, by)];
}

// ───────────────────────── Calcul des dégâts ─────────────────────────

int _bonusVsClasses(UnitDef atk, Set<String> classes) {
  if (atk.bonus.isEmpty) return 0;
  var sum = 0;
  for (final c in classes) {
    sum += atk.bonus[c] ?? 0;
  }
  return sum;
}

/// Dégâts d'une unité (définition [atk]) contre une unité cible.
int calcUnitDamage(World w, UnitDef atk, int atkPercent, Unit target) {
  final base = atk.attack + _bonusVsClasses(atk, target.def.classes);
  final raw = base * atkPercent ~/ 100;
  final type = atk.damageType == DamageType.siege
      ? DamageType.melee
      : atk.damageType;
  final d = raw - unitArmor(w, target, type);
  return d < 1 ? 1 : d;
}

/// Dégâts d'une unité contre un bâtiment.
int calcBuildingDamage(World w, UnitDef atk, int atkPercent, Building target) {
  final base = atk.attack + (atk.bonus['building'] ?? 0);
  final raw = base * atkPercent ~/ 100;
  final d = raw - buildingArmor(w, target, atk.damageType);
  return d < 1 ? 1 : d;
}

/// Dégâts d'un bâtiment (flèche) contre une unité.
int calcTowerDamage(World w, BuildingDef atk, Unit target) {
  final d = atk.attack - unitArmor(w, target, DamageType.pierce);
  return d < 1 ? 1 : d;
}

// ───────────────────────── Application des dégâts ─────────────────────────

/// Inflige [dmg] à une unité. Renvoie vrai si elle meurt. [srcOwner] reçoit
/// l'énergie du tambour et les statistiques (-1 : source neutre).
bool damageUnit(
  World w,
  Unit t,
  int dmg, {
  int srcOwner = -1,
  Unit? src,
  bool retaliate = true,
}) {
  if (!t.alive || dmg <= 0) return false;
  final c = w.balance.combat;
  final dealt = math.min(dmg, t.hp);
  t.hp -= dmg;
  if (srcOwner >= 0 && hostile(w, srcOwner, t.owner)) {
    final sp = w.players[srcOwner];
    sp.stats.damageDealt += dealt;
    sp.drum = math.min(c.drumMax, sp.drum + dealt * c.drumPerDamage);
  }
  w.events.add(
    GameEvent(EventType.underAttack, t.owner, t.id, t.tileX, t.tileY),
  );
  if (t.hp <= 0) {
    w.killUnit(t);
    if (srcOwner >= 0 && hostile(w, srcOwner, t.owner)) {
      final sp = w.players[srcOwner];
      sp.stats.unitsKilled++;
      sp.drum = math.min(c.drumMax, sp.drum + c.drumPerKill);
    }
    return true;
  }
  if (retaliate &&
      src != null &&
      src.alive &&
      t.state == UnitState.idle &&
      t.def.military &&
      !isStunned(t) &&
      (t.stance == Stance.aggressive || t.stance == Stance.defensive)) {
    issueOrder(w, t, Order.attack(src.id), queue: false);
  }
  return false;
}

/// Inflige [dmg] à un bâtiment ; le détruit (effondrement) si besoin.
bool damageBuilding(World w, Building b, int dmg, {int srcOwner = -1}) {
  if (dmg <= 0 || !w.buildings.containsKey(b.id)) return false;
  final dealt = math.min(dmg, b.hp);
  b.hp -= dmg;
  if (srcOwner >= 0 && hostile(w, srcOwner, b.owner)) {
    w.players[srcOwner].stats.damageDealt += dealt;
    final sp = w.players[srcOwner];
    sp.drum = math.min(
      w.balance.combat.drumMax,
      sp.drum + dealt * w.balance.combat.drumPerDamage ~/ 2,
    );
  }
  w.events.add(
    GameEvent(EventType.underAttack, b.owner, b.id, b.tx, b.ty),
  );
  if (b.hp > 0) return false;
  destroyBuilding(w, b, srcOwner: srcOwner);
  return true;
}

/// Détruit un bâtiment : statistiques, effondrement sur les unités voisines.
void destroyBuilding(World w, Building b, {int srcOwner = -1}) {
  final collapse = w.balance.combat.collapseDamage;
  if (collapse > 0 && !b.def.isWall && !b.def.isField) {
    for (final u in List<Unit>.of(w.units.values)) {
      if (!u.alive || u.state == UnitState.garrisoned) continue;
      final d = World.distToRect(
        u.x,
        u.y,
        b.tx,
        b.ty,
        b.def.width,
        b.def.height,
      );
      if (d <= Fx.one) {
        damageUnit(w, u, collapse, retaliate: false);
      }
    }
  }
  w.players[b.owner].stats.buildingsLost++;
  if (srcOwner >= 0 && hostile(w, srcOwner, b.owner)) {
    w.players[srcOwner].stats.buildingsDestroyed++;
  }
  w.removeBuilding(b, destroyed: true);
}

// ───────────────────────── Effets sur les unités ─────────────────────────

/// Ajoute un effet temporaire en respectant les règles anti-cumul :
/// - un même pouvoir rafraîchit sa durée au lieu de se cumuler ;
/// - un seul étourdissement à la fois, puis immunité ;
/// - nombre d'effets par unité plafonné ; les valeurs agrégées sont plafonnées
///   à la lecture (ralentissement, bonus d'attaque, armure).
void addEffect(
  World w,
  Unit t,
  EffectSpec spec,
  int powerIndex, {
  int srcOwner = -1,
  Unit? srcUnit,
}) {
  if (!t.alive) return;
  final c = w.balance.combat;
  switch (spec.kind) {
    case EffectKind.heal:
      t.hp = math.min(t.maxHp, t.hp + spec.value);
      return;
    case EffectKind.damage:
      damageUnit(w, t, spec.value, srcOwner: srcOwner, src: srcUnit);
      return;
    case EffectKind.purge:
      t.effects.removeWhere(
        (e) =>
            e.kind == EffectKind.stun ||
            e.kind == EffectKind.slow ||
            e.kind == EffectKind.root ||
            e.kind == EffectKind.dot ||
            (e.kind == EffectKind.attackPct && e.value < 0) ||
            (e.kind == EffectKind.speed && e.value < 0) ||
            (e.kind == EffectKind.armorAdd && e.value < 0),
      );
      return;
    case EffectKind.stun:
      if (hasEffect(t, EffectKind.stunImmune) || w.tick < t.stunImmuneUntil) {
        return;
      }
    case EffectKind.stunImmune:
      // Devenir immunisé lève un étourdissement en cours.
      t.effects.removeWhere((e) => e.kind == EffectKind.stun);
    case EffectKind.slow:
    case EffectKind.root:
    case EffectKind.speed:
    case EffectKind.attackPct:
    case EffectKind.armorAdd:
    case EffectKind.gatherPct:
    case EffectKind.firstHitPct:
    case EffectKind.dot:
      break;
  }
  if (spec.ticks <= 0) return;
  for (final e in t.effects) {
    final same = spec.kind == EffectKind.stun
        ? e.kind == EffectKind.stun
        : (e.kind == spec.kind && e.power == powerIndex);
    if (same) {
      if (spec.ticks > e.remaining) e.remaining = spec.ticks;
      if (spec.value.abs() > e.value.abs()) e.value = spec.value;
      return;
    }
  }
  if (t.effects.length >= c.maxEffects) return;
  t.effects.add(
    ActiveEffect(spec.kind, powerIndex, spec.ticks, spec.value, srcOwner),
  );
}

/// Décompte des effets d'une unité (début de son tick). Renvoie faux si elle
/// meurt des dégâts sur la durée.
bool tickEffects(World w, Unit u) {
  if (u.effects.isEmpty) return true;
  final immunity = w.balance.combat.stunImmunityTicks;
  for (var i = 0; i < u.effects.length;) {
    final e = u.effects[i];
    if (e.kind == EffectKind.dot && e.remaining % 10 == 0) {
      final killed = damageUnit(
        w,
        u,
        e.value,
        srcOwner: e.src,
        retaliate: false,
      );
      if (killed) return false;
    }
    e.remaining--;
    if (e.remaining <= 0) {
      if (e.kind == EffectKind.stun) {
        u.stunImmuneUntil = w.tick + immunity;
      }
      u.effects.removeAt(i);
    } else {
      i++;
    }
  }
  return true;
}

// ───────────────────────── Projectiles ─────────────────────────

/// Lance un projectile d'une unité vers sa cible. Renvoie faux si le plafond
/// de projectiles est atteint (le tir est perdu).
bool launchUnitProjectile(
  World w,
  Unit u,
  int targetId,
  int tx,
  int ty,
  int atkPercent, {
  required bool firstHit,
}) {
  if (w.projectiles.length >= w.balance.combat.maxProjectiles) return false;
  final speed = math.max(1, u.def.projectileSpeed * Fx.one ~/ 10000);
  final p = Projectile(
    id: w.newId(),
    owner: u.owner,
    srcId: u.id,
    srcUnitDef: u.def.index,
    srcBuildingDef: -1,
    targetId: targetId,
    x: u.x,
    y: u.y,
    tx: tx,
    ty: ty,
    speed: speed,
    atkPercent: atkPercent,
    ttl: w.balance.combat.projectileTtlTicks,
    firstHit: firstHit,
  );
  w.projectiles[p.id] = p;
  return true;
}

bool launchBuildingProjectile(World w, Building b, Unit target) {
  if (w.projectiles.length >= w.balance.combat.maxProjectiles) return false;
  final c = b.center;
  final speed = math.max(1, b.def.projectileSpeed * Fx.one ~/ 10000);
  final p = Projectile(
    id: w.newId(),
    owner: b.owner,
    srcId: b.id,
    srcUnitDef: -1,
    srcBuildingDef: b.def.index,
    targetId: target.id,
    x: c.x,
    y: c.y,
    tx: target.x,
    ty: target.y,
    speed: speed,
    atkPercent: 100,
    ttl: w.balance.combat.projectileTtlTicks,
  );
  w.projectiles[p.id] = p;
  return true;
}

void updateProjectiles(World w) {
  if (w.projectiles.isEmpty) return;
  for (final p in List<Projectile>.of(w.projectiles.values)) {
    final tu = w.units[p.targetId];
    final tb = w.buildings[p.targetId];
    if (tu != null && tu.alive && tu.state != UnitState.garrisoned) {
      p.tx = tu.x;
      p.ty = tu.y;
    } else if (tb != null) {
      final c = tb.center;
      p.tx = c.x;
      p.ty = c.y;
    }
    p.ttl--;
    final dx = p.tx - p.x;
    final dy = p.ty - p.y;
    final dist = Fx.isqrt(dx * dx + dy * dy);
    if (dist <= p.speed) {
      p.x = p.tx;
      p.y = p.ty;
      _impact(w, p, tu, tb);
      w.projectiles.remove(p.id);
    } else {
      p.x += dx * p.speed ~/ dist;
      p.y += dy * p.speed ~/ dist;
      if (p.ttl <= 0) w.projectiles.remove(p.id);
    }
  }
}

void _impact(World w, Projectile p, Unit? tu, Building? tb) {
  final unitDef = p.srcUnitDef >= 0 ? w.defs.units[p.srcUnitDef] : null;
  final bldDef = p.srcBuildingDef >= 0
      ? w.defs.buildings[p.srcBuildingDef]
      : null;
  final src = unitDef == null ? null : w.units[p.srcId];
  final splash = unitDef == null ? 0 : milliToFx(unitDef.splash);
  if (splash > 0 && unitDef != null) {
    // Dégâts de zone : tout ce qui est dans le rayon, amis compris.
    for (final u in List<Unit>.of(w.units.values)) {
      if (!u.alive || u.state == UnitState.garrisoned) continue;
      final dx = u.x - p.x;
      final dy = u.y - p.y;
      if (dx * dx + dy * dy > splash * splash) continue;
      damageUnit(
        w,
        u,
        calcUnitDamage(w, unitDef, p.atkPercent, u),
        srcOwner: p.owner,
        src: src,
      );
    }
    for (final b in List<Building>.of(w.buildings.values)) {
      final d = World.distToRect(
        p.x,
        p.y,
        b.tx,
        b.ty,
        b.def.width,
        b.def.height,
      );
      if (d > splash) continue;
      damageBuilding(
        w,
        b,
        calcBuildingDamage(w, unitDef, p.atkPercent, b),
        srcOwner: p.owner,
      );
    }
    return;
  }
  if (tu != null && tu.alive && tu.state != UnitState.garrisoned) {
    final dx = tu.x - p.x;
    final dy = tu.y - p.y;
    if (dx * dx + dy * dy > projectileHitFx * projectileHitFx * 4) return;
    if (unitDef != null) {
      final dmg = calcUnitDamage(w, unitDef, p.atkPercent, tu);
      final killed = damageUnit(w, tu, dmg, srcOwner: p.owner, src: src);
      if (!killed && unitDef.onHit != null) {
        addEffect(
          w,
          tu,
          unitDef.onHit!,
          -1,
          srcOwner: p.owner,
          srcUnit: src,
        );
      }
    } else if (bldDef != null) {
      damageUnit(w, tu, calcTowerDamage(w, bldDef, tu), srcOwner: p.owner);
    }
    return;
  }
  if (tb != null && unitDef != null) {
    damageBuilding(
      w,
      tb,
      calcBuildingDamage(w, unitDef, p.atkPercent, tb),
      srcOwner: p.owner,
    );
  }
}

// ───────────────────────── Bâtiments armés ─────────────────────────

void updateBuildingCombat(World w) {
  for (final b in List<Building>.of(w.buildings.values)) {
    final d = b.def;
    if (d.attack <= 0 || !b.complete) continue;
    if (w.players[b.owner].defeated) continue;
    if (b.cooldown > 0) {
      b.cooldown--;
      continue;
    }
    if ((w.tick + b.id) % 5 != 0) continue;
    final range = d.range * Fx.one + b.def.width * Fx.one ~/ 2;
    final target = _nearestHostileUnit(w, b, range);
    if (target == null) continue;
    var arrows = 1;
    if (d.garrisonArrows > 0) {
      var soldiers = 0;
      for (final id in b.garrisoned) {
        final g = w.units[id];
        if (g != null && g.def.military) soldiers++;
      }
      arrows += math.min(10, soldiers * d.garrisonArrows);
    }
    for (var i = 0; i < arrows; i++) {
      launchBuildingProjectile(w, b, target);
    }
    b.cooldown = d.attackCooldownTicks;
  }
}

Unit? _nearestHostileUnit(World w, Building b, int rangeFx) {
  final c = b.center;
  final tiles = rangeFx ~/ Fx.one + 1;
  final cx = Fx.toInt(c.x);
  final cy = Fx.toInt(c.y);
  final map = w.map;
  final sp = w.spatial;
  Unit? best;
  var bestD = 1 << 60;
  for (
    var ty = math.max(0, cy - tiles);
    ty <= math.min(map.height - 1, cy + tiles);
    ty++
  ) {
    for (
      var tx = math.max(0, cx - tiles);
      tx <= math.min(map.width - 1, cx + tiles);
      tx++
    ) {
      final cell = ty * map.width + tx;
      for (var k = sp.start[cell]; k < sp.start[cell + 1]; k++) {
        final u = w.units[sp.items[k]];
        if (u == null ||
            !u.alive ||
            u.state == UnitState.garrisoned ||
            !hostile(w, b.owner, u.owner)) {
          continue;
        }
        final dx = u.x - c.x;
        final dy = u.y - c.y;
        final d2 = dx * dx + dy * dy;
        if (d2 > rangeFx * rangeFx) continue;
        // Les soldats priment sur les villageois.
        final score = d2 + (u.def.military ? 0 : 16 * Fx.one * Fx.one);
        if (score < bestD ||
            (score == bestD && best != null && u.id < best.id)) {
          bestD = score;
          best = u;
        }
      }
    }
  }
  return best;
}

// ───────────────────────── Pouvoirs et sorts ─────────────────────────

/// Index du pouvoir d'une unité à l'emplacement [slot] (ou -1).
PowerDef? powerOf(World w, Unit u, int slot) {
  if (slot < 0 || slot >= u.def.powers.length) return null;
  return w.defs.power(u.def.powers[slot]);
}

/// Unités affectées par une zone centrée en (cx, cy).
List<Unit> _unitsInArea(
  World w,
  int cx,
  int cy,
  int radiusFx,
  PowerDef pd,
  int casterOwner,
  Unit? caster,
) {
  final out = <Unit>[];
  final r2 = radiusFx * radiusFx;
  for (final u in w.units.values) {
    if (!u.alive || u.state == UnitState.garrisoned) continue;
    if (caster != null && u.id == caster.id && !pd.includeSelf) continue;
    final ally = !hostile(w, casterOwner, u.owner);
    switch (pd.affects) {
      case PowerAffects.allies:
        if (!ally) continue;
      case PowerAffects.enemies:
        if (ally) continue;
      case PowerAffects.all:
        break;
    }
    final dx = u.x - cx;
    final dy = u.y - cy;
    if (dx * dx + dy * dy <= r2) out.add(u);
  }
  return out;
}

void _applyPower(
  World w,
  PowerDef pd,
  List<Unit> targets,
  int casterOwner,
  Unit? caster,
) {
  for (final t in targets) {
    for (final spec in pd.effects) {
      addEffect(w, t, spec, pd.index, srcOwner: casterOwner, srcUnit: caster);
      if (!t.alive) break;
    }
  }
}

/// Lance le pouvoir [slot] d'une unité. Une commande invalide (cible morte,
/// hors de portée, recharge, âge) ne consomme rien.
CmdResult usePower(
  World w,
  int owner,
  int unitId,
  int slot,
  int tx,
  int ty,
  int targetId,
) {
  final u = w.units[unitId];
  if (u == null || !u.alive || u.state == UnitState.garrisoned) {
    return CmdResult.notFound;
  }
  if (u.owner != owner) return CmdResult.notOwned;
  final pd = powerOf(w, u, slot);
  if (pd == null || pd.aura || pd.isSpell || slot >= u.powerCd.length) {
    return CmdResult.wrongTarget;
  }
  if (isStunned(u)) return CmdResult.nothingToDo;
  final p = w.players[owner];
  if (pd.age > p.age) return CmdResult.locked;
  if (u.powerCd[slot] > 0) return CmdResult.nothingToDo;

  int cx;
  int cy;
  Unit? primary;
  switch (pd.target) {
    case PowerTarget.self:
      cx = u.x;
      cy = u.y;
    case PowerTarget.unit:
      primary = w.units[targetId];
      if (primary == null ||
          !primary.alive ||
          primary.state == UnitState.garrisoned) {
        return CmdResult.notFound;
      }
      final ally = !hostile(w, owner, primary.owner);
      if (pd.affects == PowerAffects.enemies && ally) {
        return CmdResult.wrongTarget;
      }
      if (pd.affects == PowerAffects.allies && !ally) {
        return CmdResult.wrongTarget;
      }
      cx = primary.x;
      cy = primary.y;
      final d = Fx.isqrt((cx - u.x) * (cx - u.x) + (cy - u.y) * (cy - u.y));
      if (d > pd.rangeTiles * Fx.one + 64) return CmdResult.outOfRange;
    case PowerTarget.ground:
      if (!w.map.inBounds(tx, ty)) return CmdResult.invalid;
      cx = Fx.tileCenter(tx);
      cy = Fx.tileCenter(ty);
      final d = Fx.isqrt((cx - u.x) * (cx - u.x) + (cy - u.y) * (cy - u.y));
      if (d > pd.rangeTiles * Fx.one + 64) return CmdResult.outOfRange;
  }

  final List<Unit> targets;
  if (pd.target == PowerTarget.unit && pd.radius == 0) {
    targets = <Unit>[primary!];
  } else if (pd.target == PowerTarget.self && pd.radius == 0) {
    targets = <Unit>[u];
  } else {
    targets = _unitsInArea(w, cx, cy, milliToFx(pd.radius), pd, owner, u);
  }
  u.powerCd[slot] = pd.cooldownTicks;
  p.stats.powersUsed++;
  _applyPower(w, pd, targets, owner, u);
  return CmdResult.ok;
}

/// Lance un sort de bataille à une case : consomme l'énergie du tambour.
CmdResult castSpell(World w, int owner, int powerIndex, int tx, int ty) {
  if (powerIndex < 0 || powerIndex >= w.defs.powers.length) {
    return CmdResult.invalid;
  }
  final pd = w.defs.powers[powerIndex];
  if (!pd.isSpell) return CmdResult.wrongTarget;
  if (!w.map.inBounds(tx, ty)) return CmdResult.invalid;
  final p = w.players[owner];
  if (p.defeated) return CmdResult.nothingToDo;
  if (p.drum < pd.drumCost) return CmdResult.cannotAfford;
  if (powerIndex >= p.spellCd.length || p.spellCd[powerIndex] > 0) {
    return CmdResult.nothingToDo;
  }
  p.drum -= pd.drumCost;
  p.spellCd[powerIndex] = pd.cooldownTicks;
  p.stats.spellsCast++;
  final targets = _unitsInArea(
    w,
    Fx.tileCenter(tx),
    Fx.tileCenter(ty),
    milliToFx(pd.radius),
    pd,
    owner,
    null,
  );
  _applyPower(w, pd, targets, owner, null);
  return CmdResult.ok;
}

/// Recharges des pouvoirs et auras : une fois par tick pour les recharges,
/// toutes les `auraPeriodTicks` pour les auras.
void updatePowers(World w) {
  for (final p in w.players) {
    for (var i = 0; i < p.spellCd.length; i++) {
      if (p.spellCd[i] > 0) p.spellCd[i]--;
    }
  }
  final period = w.balance.combat.auraPeriodTicks;
  if (w.tick % period != 0) return;
  for (final u in List<Unit>.of(w.units.values)) {
    if (!u.alive || u.def.powers.isEmpty || u.state == UnitState.garrisoned) {
      continue;
    }
    if (isStunned(u)) continue;
    for (final id in u.def.powers) {
      final pd = w.defs.power(id);
      if (!pd.aura) continue;
      final targets = _unitsInArea(
        w,
        u.x,
        u.y,
        milliToFx(pd.radius),
        pd,
        u.owner,
        u,
      );
      for (final t in targets) {
        for (final spec in pd.effects) {
          addEffect(w, t, spec, pd.index, srcOwner: u.owner);
        }
      }
    }
  }
}

// ───────────────────────── Statistiques dérivées ─────────────────────────

/// Applique les bonus de PV d'une recherche aux unités existantes.
void refreshUnitHp(World w, int owner) {
  final p = w.players[owner];
  for (final u in w.units.values) {
    if (u.owner != owner || !u.alive) continue;
    final target = u.def.hp * (100 + p.mod('hp', u.def)) ~/ 100;
    if (target > u.maxHp) {
      u.hp += target - u.maxHp;
      u.maxHp = target;
    }
  }
}

/// PV maximum d'une unité neuve selon les bonus du joueur.
int maxHpFor(World w, int owner, UnitDef def) {
  final v = def.hp * (100 + w.players[owner].mod('hp', def)) ~/ 100;
  return v < 1 ? 1 : v;
}
