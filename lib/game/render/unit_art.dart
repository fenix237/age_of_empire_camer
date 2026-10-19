import 'dart:math' as math;
import 'dart:ui';

import 'package:age_of_empire_camer/game/render/assets.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';

/// Personnages articulés dessinés par le code (en attendant les atlas de la
/// Phase 9) : squelette simple (hanche, épaule, tête, deux bras, deux jambes),
/// outil en main et pose calculée à partir du geste réel de la simulation
/// ([UnitAction]) : couper, cueillir, miner, cultiver, bâtir, chasser, frapper,
/// tirer. Tout est dessiné « tourné vers +x » puis retourné selon l'orientation.
/// Les unités sont en « unités de dessin » (1 = 1 px à l'échelle 1).

const double _tau = math.pi * 2;

const List<Color> _skins = <Color>[
  Color(0xFF8A5A3C),
  Color(0xFF6B4228),
  Color(0xFFA06B47),
  Color(0xFF5A3720),
];
const List<Color> _hairs = <Color>[
  Color(0xFF1B130E),
  Color(0xFF2A1B12),
  Color(0xFF120D0A),
];
const Color _wood = Color(0xFF3B2A1A);
const Color _woodLight = Color(0xFF8A6238);
const Color _steel = Color(0xFF9AA3AB);
const Color _dark = Color(0xFF2B2622);

Color _heroAccent(String id) => switch (id) {
  'hero_mbarga' => const Color(0xFFE6B422),
  'hero_sanaga' => const Color(0xFF3FB3C7),
  'hero_ngolo' => const Color(0xFFE0612B),
  'hero_dikoume' => const Color(0xFFB8E04A),
  'hero_kaba' => const Color(0xFF8E4FC9),
  _ => const Color(0xFFE6B422),
};

// ───────────────────────── Courbes ─────────────────────────

double _fract(double v) => v - v.floorToDouble();

double _ease(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

double _mix(double a, double b, double t) => a + (b - a) * t;

/// Direction d'un manche : 0 = vers le haut, positif = bascule vers l'avant.
Offset _dir(double ang) => Offset(math.sin(ang), -math.cos(ang));

/// Un coup : armement lent (0 → -1), frappe vive (-1 → 1), retour (1 → 0).
double _strike(double p) {
  if (p < 0.55) return -_ease(p / 0.55);
  if (p < 0.68) return -1 + 2 * _ease((p - 0.55) / 0.13);
  return 1 - _ease((p - 0.68) / 0.32);
}

/// Progression 0..1 de l'effet d'impact (nul en dehors de la fenêtre).
double? _impactT(double p) => p >= 0.66 && p < 0.92 ? (p - 0.66) / 0.26 : null;

// ───────────────────────── Pose ─────────────────────────

enum _Tool {
  none,
  axe,
  pick,
  hoe,
  hammer,
  warHammer,
  spear,
  lance,
  sword,
  staff,
  bow,
  net,
}

enum _Fx { none, chips, sparkStone, sparkIron, sparkGold, dust, hit }

class _Pose {
  /// Décalage avant des épaules et abaissement du buste.
  double lean = 0;
  double crouch = 0;
  double bob = 0;

  /// Pieds (x relatif, hauteur de levée).
  double legF = 2.5;
  double legB = -2.5;
  double liftF = 0;
  double liftB = 0;

  Offset? handF;
  Offset? handB;
  _Tool tool = _Tool.none;
  double toolAngle = 0;

  /// Deux mains sur l'outil (le bras arrière passe devant le buste).
  bool two = false;

  /// Tension de l'arc (0..1) ; -1 : arc non bandé.
  double pull = -1;
  bool arrow = false;

  /// Baie tenue dans la main avant (cueillette).
  bool berry = false;

  _Fx fx = _Fx.none;
  double? impact;
  Offset fxAt = const Offset(22, -7);

  Offset get hip => Offset(0, -11 + crouch * 0.35 + bob);
  Offset get sh => Offset(lean, -21 + crouch * 0.85 + bob);
  Offset get head => Offset(lean * 1.25, -27.5 + crouch + bob);
}

_Tool _soldierTool(UnitDef d) => switch (d.id) {
  'spearman' || 'river_guard' => _Tool.spear,
  'iron_warrior' || 'royal_guard' || 'hero_kaba' => _Tool.sword,
  'horseman' => _Tool.lance,
  'forge_hammer' || 'hero_ngolo' => _Tool.warHammer,
  'hero_dikoume' => _Tool.staff,
  'hero_mbarga' => _Tool.hammer,
  'net_thrower' => _Tool.net,
  'archer' || 'wind_rider' || 'hero_sanaga' => _Tool.bow,
  _ => d.range > 0 ? _Tool.bow : (d.villager ? _Tool.none : _Tool.sword),
};

Color? _shieldOf(UnitDef d) => switch (d.id) {
  'spearman' => const Color(0xFF8A5A2B),
  'river_guard' => const Color(0xFF2E7BD6),
  'iron_warrior' => _steel,
  'royal_guard' => const Color(0xFFE6B422),
  _ => null,
};

/// Position de la main qui tient l'arme au repos ou en marche.
void _restGrip(_Pose p) {
  final sh = p.sh;
  switch (p.tool) {
    case _Tool.spear:
    case _Tool.lance:
    case _Tool.staff:
      p
        ..handF = sh + const Offset(7, 5)
        ..toolAngle = 0.1;
    case _Tool.sword:
      p
        ..handF = sh + const Offset(6.5, 8)
        ..toolAngle = 0.95;
    case _Tool.warHammer:
      p
        ..handF = sh + const Offset(6, 3)
        ..toolAngle = 0.55;
    case _Tool.hammer:
      p
        ..handF = sh + const Offset(6.5, 8)
        ..toolAngle = 0.8;
    case _Tool.bow:
      p
        ..handF = sh + const Offset(8, 4)
        ..toolAngle = 0;
    case _Tool.net:
      p.handF = sh + const Offset(7, 8);
    case _Tool.none:
    case _Tool.axe:
    case _Tool.pick:
    case _Tool.hoe:
      break;
  }
}

/// Dispositions des bras quand l'unité porte une charge.
void _carryPose(_Pose p, int carry) {
  final sh = p.sh;
  switch (carry) {
    case 1: // bois : tronc sur l'épaule
      p
        ..lean += 1.5
        ..handF = sh + const Offset(7, -3)
        ..handB = sh + const Offset(-4, -4);
    case 0: // nourriture : panier dans le dos
      p.handB = sh + const Offset(-5, 6);
    case 2:
    case 3:
    case 4: // sac de minerai
      p
        ..lean += 2
        ..handB = sh + const Offset(-4, -3);
  }
}

_Pose _poseFor(UnitDef def, SpriteContext ctx) {
  final p = _Pose()..tool = _soldierTool(def);
  final seed = ctx.seed.toDouble();
  final mounted = def.classes.contains('cavalry');
  switch (ctx.action) {
    case UnitAction.idle:
      p
        ..bob = math.sin(ctx.time * 2 + seed) * 0.35
        ..handB = null;
      _restGrip(p);
      if (def.villager && ctx.carry >= 0) _carryPose(p, ctx.carry);
    case UnitAction.walk:
      final ph = _fract(ctx.time * (mounted ? 1.9 : 1.25) + seed * 0.137);
      final sn = math.sin(ph * _tau);
      final cs = math.cos(ph * _tau);
      p
        ..legF = sn * 5.5
        ..legB = -sn * 5.5
        ..liftF = math.max<double>(0, cs) * 2.6
        ..liftB = math.max<double>(0, -cs) * 2.6
        ..bob = -sn.abs() * 1.2
        ..lean = 0.8;
      final sh = p.sh;
      p
        ..handF = sh + Offset(-sn * 5 + 2.5, 10)
        ..handB = sh + Offset(sn * 5 - 1, 10);
      _restGrip(p);
      if (def.villager && ctx.carry >= 0) _carryPose(p, ctx.carry);
    case UnitAction.chop:
    case UnitAction.mine:
    case UnitAction.farm:
    case UnitAction.build:
      _swingPose(p, ctx, def);
    case UnitAction.forage:
      final ph = _fract(ctx.time * 0.55 + seed * 0.17);
      final u = ph < 0.35
          ? _ease(ph / 0.35)
          : (ph < 0.5 ? 1.0 : (ph < 0.85 ? 1 - _ease((ph - 0.5) / 0.35) : 0.0));
      p
        ..legF = 3.5
        ..legB = -3.5
        ..crouch = 2 + 4 * u
        ..lean = 2 + 5 * u;
      final sh = p.sh;
      final wiggle = ph >= 0.35 && ph < 0.5 ? math.sin(ph * 90) * 0.8 : 0.0;
      p
        ..handF = Offset.lerp(
          sh + const Offset(-2, 9),
          Offset(21 + wiggle, -5),
          u,
        )
        ..handB = sh + const Offset(1, 10)
        ..berry = ph >= 0.5 && ph < 0.85;
    case UnitAction.hunt:
      _thrustPose(p, ctx, def, _Tool.spear, 1, _Fx.hit);
    case UnitAction.melee:
      if (p.tool == _Tool.spear || p.tool == _Tool.lance) {
        _thrustPose(p, ctx, def, p.tool, 1, _Fx.hit);
      } else {
        _swingPose(p, ctx, def);
      }
    case UnitAction.shoot:
      _shootPose(p, ctx, def);
  }
  return p;
}

/// Gestes d'arc de cercle : hache, pioche, houe, marteau, épée, masse.
void _swingPose(_Pose p, SpriteContext ctx, UnitDef def) {
  final seed = ctx.seed.toDouble();
  late double rate;
  late double lo;
  late double hi;
  late double bend;
  late double reach;
  switch (ctx.action) {
    case UnitAction.chop:
      p
        ..tool = _Tool.axe
        ..fx = _Fx.chips
        ..fxAt = const Offset(24, -9);
      (rate, lo, hi, bend, reach) = (0.85, -0.55, 2.3, 3.0, 9.5);
    case UnitAction.mine:
      p
        ..tool = _Tool.pick
        ..fx = switch (ctx.carry) {
          4 => _Fx.sparkGold,
          3 => _Fx.sparkIron,
          _ => _Fx.sparkStone,
        }
        ..fxAt = const Offset(23, -6);
      (rate, lo, hi, bend, reach) = (0.8, -0.7, 2.2, 3.0, 9.5);
    case UnitAction.farm:
      p
        ..tool = _Tool.hoe
        ..fx = _Fx.dust
        ..fxAt = const Offset(24, -3);
      (rate, lo, hi, bend, reach) = (0.7, 0.2, 2.1, 3.0, 9.5);
    case UnitAction.build:
      p
        ..tool = _Tool.hammer
        ..fx = _Fx.dust
        ..fxAt = const Offset(21, -8);
      (rate, lo, hi, bend, reach) = (1.7, 0.4, 1.9, 2.0, 7.0);
    case UnitAction.melee:
    case UnitAction.idle:
    case UnitAction.walk:
    case UnitAction.forage:
    case UnitAction.hunt:
    case UnitAction.shoot: // mêlée à l'arme
      p
        ..fx = _Fx.hit
        ..fxAt = const Offset(24, -14);
      (rate, lo, hi, bend, reach) = (1.0, -0.5, 2.2, 2.0, 9.5);
  }
  final ph = _fract(ctx.time * rate + seed * 0.21);
  final e = (_strike(ph) + 1) / 2;
  final ang = _mix(lo, hi, e);
  p
    ..impact = _impactT(ph)
    ..legF = 4
    ..legB = -4
    ..lean = _mix(-1.5, 2 + bend, e)
    ..crouch = _mix(0, bend, e)
    ..toolAngle = ang
    ..two =
        ctx.action != UnitAction.build &&
        !(ctx.action == UnitAction.melee &&
            (p.tool == _Tool.sword || p.tool == _Tool.hammer));
  final sh = p.sh;
  final hand = sh + _dir(ang * 0.85) * reach;
  p.handF = hand;
  if (p.two) {
    p.handB = hand - _dir(ang) * 3.2;
  } else {
    p.handB = sh + const Offset(3, 8);
  }
}

/// Coup d'estoc (lance, épieu) : armement, détente, retour.
void _thrustPose(
  _Pose p,
  SpriteContext ctx,
  UnitDef def,
  _Tool tool,
  double rate,
  _Fx fx,
) {
  final ph = _fract(ctx.time * rate + ctx.seed * 0.21);
  final reach = (_strike(ph) + 1) / 2;
  p
    ..tool = tool
    ..fx = fx
    ..fxAt = Offset(tool == _Tool.lance ? 32 : 30, -14)
    ..impact = _impactT(ph)
    ..legF = 4.5
    ..legB = -4.5
    ..lean = 1 + 4 * reach
    ..toolAngle = 1.3 - reach * 0.12
    ..two = ctx.action == UnitAction.hunt || tool == _Tool.spear;
  final sh = p.sh;
  final hand = sh + Offset(2 + reach * 9, 5);
  p
    ..handF = hand
    ..handB = p.two ? hand - _dir(p.toolAngle) * 5 : sh + const Offset(2, 8);
}

/// Tir : l'arc se bande, la corde est lâchée ; filet : lancer par-dessus l'épaule.
void _shootPose(_Pose p, SpriteContext ctx, UnitDef def) {
  final ph = _fract(ctx.time * 0.9 + ctx.seed * 0.19);
  if (p.tool == _Tool.net) {
    final e = _ease(ph / 0.7);
    final ang = ph < 0.7
        ? _mix(-0.4, 0.9, e)
        : _mix(0.9, 1.9, _ease((ph - 0.7) / 0.1));
    p
      ..lean = ph < 0.7 ? _mix(0, -1.5, e) : 3
      ..legF = 3.5
      ..legB = -3.5;
    final sh = p.sh;
    p
      ..handF = sh + _dir(ang) * 10
      ..handB = sh + const Offset(1, 9)
      ..arrow = ph < 0.72;
    return;
  }
  p.tool = _Tool.bow;
  final pull = ph < 0.6
      ? _ease(ph / 0.6)
      : (ph < 0.7 ? 1.0 : (ph < 0.78 ? 1 - _ease((ph - 0.7) / 0.08) : 0.0));
  p
    ..legF = 4
    ..legB = -4
    ..lean = 1 - pull * 1.5
    ..pull = pull
    ..arrow = ph < 0.72;
  final sh = p.sh;
  final grip = sh + const Offset(10.5, 0.5);
  p
    ..handF = grip
    ..handB = grip + Offset(-pull * 10, 0.5)
    ..toolAngle = 0;
}

// ───────────────────────── Dessin principal ─────────────────────────

SpriteDrawer unitArt(UnitDef def) => (c, a, ctx) {
  final id = def.id;
  final hero = def.isHero;
  final s = ctx.scale * (hero ? 1.22 : 1.0);
  final team = ctx.flash ? const Color(0xFFFFFFFF) : teamColor(ctx.team);

  // Ombre.
  final shadowW = (def.classes.contains('siege') ? 38 : 26) * s;
  c.drawOval(
    Rect.fromCenter(center: a, width: shadowW, height: 11 * s),
    Paint()..color = const Color(0x55000000),
  );

  // Aura des héros.
  if (hero) {
    c.drawOval(
      Rect.fromCenter(center: a, width: 40 * s, height: 18 * s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _heroAccent(id).withValues(alpha: 0.65),
    );
  }

  if (id == 'raven') {
    _raven(c, a, s, Paint()..color = team, ctx);
    return;
  }

  c.save();
  if (!ctx.faceRight) {
    c
      ..translate(a.dx, a.dy)
      ..scale(-1, 1)
      ..translate(-a.dx, -a.dy);
  }
  if (id == 'catapult') {
    _catapult(c, a, s, Paint()..color = team, ctx);
  } else {
    _human(c, a, s, def, ctx, team);
  }
  c.restore();
};

void _human(
  Canvas c,
  Offset a,
  double s,
  UnitDef def,
  SpriteContext ctx,
  Color team,
) {
  final p = _poseFor(def, ctx);
  final mounted = def.classes.contains('cavalry');
  if (mounted) _horse(c, a, s, ctx);
  final lift = mounted ? 9.0 : 0.0;
  final o = a.translate(0, -lift * s);
  Offset pt(Offset v) => Offset(o.dx + v.dx * s, o.dy + v.dy * s);

  final skinCol = _skins[ctx.seed.abs() % _skins.length];
  final hairCol = _hairs[(ctx.seed.abs() ~/ 4) % _hairs.length];
  final skin = Paint()..color = skinCol;
  final cloth = Paint()..color = team;
  final pants = Paint()
    ..color = def.villager ? const Color(0xFF6B5237) : const Color(0xFF3A3028);
  final shield = _shieldOf(def);
  final sh = p.sh;
  final hip = p.hip;

  // Charge dans le dos (derrière le buste).
  final carrying =
      def.villager &&
      ctx.carry >= 0 &&
      (ctx.action == UnitAction.walk || ctx.action == UnitAction.idle);
  if (carrying) {
    _loadBehind(c, pt(sh), s, ctx.carry);
  }
  if (ctx.action == UnitAction.forage) {
    _basket(c, pt(const Offset(-15, -3)), s, full: true);
  }

  // Cape des héros, derrière le buste.
  if (def.isHero) {
    final accent = _heroAccent(def.id);
    c.drawPath(
      Path()
        ..moveTo(o.dx + (sh.dx - 3) * s, o.dy + (sh.dy + 1) * s)
        ..lineTo(o.dx + (sh.dx - 11) * s, o.dy - 3 * s)
        ..lineTo(o.dx + (hip.dx - 1) * s, o.dy + (hip.dy + 3) * s)
        ..close(),
      Paint()..color = accent.withValues(alpha: 0.85),
    );
  }

  // Jambes (cavalier : jambes pendantes simples).
  void leg(double fx, double lift, {bool back = false}) {
    final foot = Offset(fx, -lift);
    final knee =
        Offset.lerp(hip + const Offset(0, 2), foot, 0.5)! +
        Offset(1.6 * (back ? -0.6 : 1), 0);
    final w = 3.4 * s;
    c
      ..drawLine(
        pt(hip + const Offset(0, 2)),
        pt(knee),
        pants
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(pt(knee), pt(foot), pants)
      ..drawOval(
        Rect.fromCenter(
          center: pt(foot + const Offset(1.4, -0.5)),
          width: 5.4 * s,
          height: 2.6 * s,
        ),
        Paint()..color = _dark,
      );
  }

  if (mounted) {
    c.drawLine(
      pt(hip + const Offset(0, 2)),
      pt(const Offset(4, -2)),
      pants
        ..strokeWidth = 3.4 * s
        ..strokeCap = StrokeCap.round,
    );
  } else {
    leg(p.legB, p.liftB, back: true);
  }

  // Bras arrière avant le buste, sauf s'il tient l'outil ou le bouclier.
  final handB = p.handB ?? sh + const Offset(-1, 10);
  final backInFront = p.two || shield != null;
  if (!backInFront) _arm(c, pt(sh), pt(handB), s, skin, cloth);

  // Torse (tunique).
  final tunic = Path()
    ..moveTo(o.dx + (sh.dx - 4.6) * s, o.dy + sh.dy * s)
    ..lineTo(o.dx + (sh.dx + 4.6) * s, o.dy + sh.dy * s)
    ..lineTo(o.dx + (hip.dx + 4.6) * s, o.dy + (hip.dy + 4) * s)
    ..lineTo(o.dx + (hip.dx - 4.6) * s, o.dy + (hip.dy + 4) * s)
    ..close();
  c
    ..drawPath(tunic, cloth)
    ..drawPath(
      tunic,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0x66000000),
    )
    // Ceinture.
    ..drawLine(
      pt(hip + const Offset(-4.2, 0.5)),
      pt(hip + const Offset(4.2, 0.5)),
      Paint()
        ..color = const Color(0xCC2B1B10)
        ..strokeWidth = 1.8 * s,
    );
  if (def.id == 'hero_mbarga') {
    c
      ..drawRect(
        Rect.fromCenter(
          center: pt(hip + const Offset(4.5, 3)),
          width: 7 * s,
          height: 8 * s,
        ),
        Paint()..color = const Color(0xFF8A5A2B),
      )
      ..drawOval(
        Rect.fromCenter(
          center: pt(hip + const Offset(4.5, -1)),
          width: 7 * s,
          height: 3 * s,
        ),
        Paint()..color = const Color(0xFFE8D8B0),
      );
  }

  if (!mounted) leg(p.legF, p.liftF);

  // Tête.
  final head = pt(p.head);
  c.drawCircle(head, 4.7 * s, skin);
  final hair = Paint()..color = hairCol;
  if (ctx.faceDown) {
    c
      ..drawArc(
        Rect.fromCenter(center: head, width: 9.6 * s, height: 9.6 * s),
        math.pi * 0.95,
        math.pi * 1.1,
        true,
        hair,
      )
      ..drawCircle(
        head.translate(2.2 * s, -0.3 * s),
        0.75 * s,
        Paint()..color = const Color(0xFF120D0A),
      )
      ..drawCircle(head.translate(4.6 * s, 0.6 * s), 1.1 * s, skin);
  } else {
    c.drawCircle(head, 4.7 * s, hair);
  }
  _headgear(c, head, s, def, ctx, team);
  if (def.isHero) _crown(c, head, s, _heroAccent(def.id));

  // Bouclier / bras arrière devant le buste.
  if (backInFront) {
    _arm(c, pt(sh), pt(handB), s, skin, cloth);
    if (shield != null) {
      _shield(c, pt(handB + const Offset(1.5, -1)), s, shield);
    }
  }

  // Arme / outil et bras avant.
  final handF = p.handF ?? sh + const Offset(1, 10);
  _arm(c, pt(sh), pt(handF), s, skin, cloth);
  _drawTool(c, pt(handF), s, p, def, ctx, team);
  c.drawCircle(pt(handF), 1.6 * s, skin);
  if (p.two && p.handB != null) c.drawCircle(pt(handB), 1.6 * s, skin);

  // Charge portée devant (tronc sur l'épaule) et baie cueillie.
  if (def.villager &&
      ctx.carry >= 0 &&
      (ctx.action == UnitAction.walk || ctx.action == UnitAction.idle)) {
    _loadFront(c, pt(sh), s, ctx.carry);
  }
  if (p.berry) {
    c.drawCircle(
      pt(handF).translate(1 * s, -1.5 * s),
      1.8 * s,
      Paint()..color = const Color(0xFFC83A56),
    );
  }

  _drawFx(c, o, s, p, ctx);
}

// ───────────────────────── Membres, charges, outils ─────────────────────────

void _arm(Canvas c, Offset from, Offset to, double s, Paint skin, Paint cloth) {
  final d = to - from;
  final len = d.distance;
  if (len < 0.1) return;
  final n = Offset(-d.dy, d.dx) / len;
  final elbow = Offset.lerp(from, to, 0.5)! + n * (1.7 * s);
  c
    ..drawLine(
      from,
      elbow,
      cloth
        ..strokeWidth = 3.6 * s
        ..strokeCap = StrokeCap.round,
    )
    ..drawLine(
      elbow,
      to,
      skin
        ..strokeWidth = 2.6 * s
        ..strokeCap = StrokeCap.round,
    );
}

void _headgear(
  Canvas c,
  Offset head,
  double s,
  UnitDef def,
  SpriteContext ctx,
  Color team,
) {
  final id = def.id;
  if (def.villager) {
    switch (ctx.action) {
      case UnitAction.farm: // chapeau de paille
        c
          ..drawOval(
            Rect.fromCenter(
              center: head.translate(0, -3 * s),
              width: 16 * s,
              height: 4.6 * s,
            ),
            Paint()..color = const Color(0xFFD9B95A),
          )
          ..drawArc(
            Rect.fromCenter(
              center: head.translate(0, -3.6 * s),
              width: 9 * s,
              height: 8 * s,
            ),
            math.pi,
            math.pi,
            true,
            Paint()..color = const Color(0xFFE6C96E),
          );
      case UnitAction.mine: // calot de cuir et petite lampe
        c
          ..drawArc(
            Rect.fromCenter(center: head, width: 10.4 * s, height: 10.4 * s),
            math.pi,
            math.pi,
            true,
            Paint()..color = const Color(0xFF5A4630),
          )
          ..drawCircle(
            head.translate(3.8 * s, -3.4 * s),
            1.2 * s,
            Paint()..color = const Color(0xFFFFD35A),
          );
      case UnitAction.idle:
      case UnitAction.walk:
      case UnitAction.chop:
      case UnitAction.forage:
      case UnitAction.hunt:
      case UnitAction.build:
      case UnitAction.melee:
      case UnitAction.shoot: // bandeau
        c
          ..drawRect(
            Rect.fromCenter(
              center: head.translate(0, -2.2 * s),
              width: 9.8 * s,
              height: 2.2 * s,
            ),
            Paint()..color = team,
          )
          ..drawLine(
            head.translate(-4.6 * s, -2.2 * s),
            head.translate(-7.5 * s, -0.5 * s),
            Paint()
              ..color = team
              ..strokeWidth = 1.8 * s
              ..strokeCap = StrokeCap.round,
          );
    }
    return;
  }
  switch (id) {
    case 'river_guard':
      _helmet(c, head, s, const Color(0xFF2E7BD6));
    case 'iron_warrior':
      _helmet(c, head, s, _steel);
    case 'royal_guard':
      _helmet(c, head, s, const Color(0xFFE6B422));
      c.drawLine(
        head.translate(0, -5 * s),
        head.translate(-3 * s, -12 * s),
        Paint()
          ..color = const Color(0xFFD64545)
          ..strokeWidth = 3 * s
          ..strokeCap = StrokeCap.round,
      );
    case 'forge_hammer':
      _helmet(c, head, s, const Color(0xFF55555E));
    case 'horseman':
      _helmet(c, head, s, const Color(0xFF7C5A33));
    default:
      // Bandeau de l'équipe pour les autres combattants légers.
      c.drawRect(
        Rect.fromCenter(
          center: head.translate(0, -2.2 * s),
          width: 9.8 * s,
          height: 2 * s,
        ),
        Paint()..color = team,
      );
  }
}

void _crown(Canvas c, Offset head, double s, Color accent) {
  c.drawPath(
    Path()
      ..moveTo(head.dx - 6 * s, head.dy - 4 * s)
      ..lineTo(head.dx - 4 * s, head.dy - 10 * s)
      ..lineTo(head.dx - 1 * s, head.dy - 5.5 * s)
      ..lineTo(head.dx + 1 * s, head.dy - 11 * s)
      ..lineTo(head.dx + 4 * s, head.dy - 5.5 * s)
      ..lineTo(head.dx + 6 * s, head.dy - 10 * s)
      ..lineTo(head.dx + 6 * s, head.dy - 4 * s)
      ..close(),
    Paint()..color = accent,
  );
}

void _helmet(Canvas c, Offset head, double s, Color col) {
  c
    ..drawArc(
      Rect.fromCenter(center: head, width: 10.8 * s, height: 10.8 * s),
      math.pi,
      math.pi,
      true,
      Paint()..color = col,
    )
    ..drawLine(
      head.translate(-5.4 * s, 0),
      head.translate(5.4 * s, 0),
      Paint()
        ..color = const Color(0x66000000)
        ..strokeWidth = 1.2,
    );
}

void _shield(Canvas c, Offset at, double s, Color col) {
  final r = Rect.fromCenter(center: at, width: 9 * s, height: 15 * s);
  c
    ..drawOval(r, Paint()..color = col)
    ..drawOval(
      r.deflate(1.8 * s),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x44FFFFFF),
    )
    ..drawOval(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x88000000),
    );
}

/// Panier d'osier ; [full] ajoute des baies.
void _basket(Canvas c, Offset at, double s, {required bool full}) {
  final r = Rect.fromCenter(
    center: at.translate(0, -2 * s),
    width: 9 * s,
    height: 6 * s,
  );
  c
    ..drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(2 * s)),
      Paint()..color = const Color(0xFFB8903F),
    )
    ..drawLine(
      r.centerLeft.translate(1 * s, 0),
      r.centerRight.translate(-1 * s, 0),
      Paint()
        ..color = const Color(0x55000000)
        ..strokeWidth = 0.8,
    );
  if (full) {
    final b = Paint()..color = const Color(0xFFC83A56);
    for (var i = 0; i < 4; i++) {
      c.drawCircle(
        r.topCenter.translate((i - 1.5) * 2.2 * s, -0.4 * s),
        1.4 * s,
        b,
      );
    }
  }
}

Color _oreColor(int res) => switch (res) {
  2 => const Color(0xFF9B9B9B),
  3 => const Color(0xFF6E8CA8),
  _ => const Color(0xFFE6B422),
};

/// Charges portées dans le dos : panier de nourriture, sac de minerai.
void _loadBehind(Canvas c, Offset sh, double s, int carry) {
  switch (carry) {
    case 0:
      _basket(c, sh.translate(-7 * s, 7 * s), s, full: true);
    case 2:
    case 3:
    case 4:
      c
        ..drawOval(
          Rect.fromCenter(
            center: sh.translate(-5 * s, -2 * s),
            width: 11 * s,
            height: 12 * s,
          ),
          Paint()..color = const Color(0xFF7A6A4A),
        )
        ..drawCircle(
          sh.translate(-5 * s, -6 * s),
          2.4 * s,
          Paint()..color = _oreColor(carry),
        );
  }
}

/// Tronc porté sur l'épaule (devant le buste).
void _loadFront(Canvas c, Offset sh, double s, int carry) {
  if (carry != 1) return;
  final log = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: sh.translate(1 * s, -4 * s),
      width: 24 * s,
      height: 5 * s,
    ),
    Radius.circular(2.4 * s),
  );
  c
    ..drawRRect(log, Paint()..color = const Color(0xFF7A5230))
    ..drawOval(
      Rect.fromCenter(
        center: sh.translate(13 * s, -4 * s),
        width: 3.4 * s,
        height: 5 * s,
      ),
      Paint()..color = const Color(0xFFD9B27A),
    )
    ..drawLine(
      sh.translate(-8 * s, -4.6 * s),
      sh.translate(9 * s, -4.6 * s),
      Paint()
        ..color = const Color(0x33000000)
        ..strokeWidth = 1,
    );
}

void _drawTool(
  Canvas c,
  Offset hand,
  double s,
  _Pose p,
  UnitDef def,
  SpriteContext ctx,
  Color team,
) {
  final tool = p.tool;
  if (tool == _Tool.none) return;
  if (tool == _Tool.bow) {
    _bow(c, hand, s, p);
    return;
  }
  if (tool == _Tool.net) {
    if (p.arrow) {
      c.drawCircle(
        hand.translate(1 * s, -3 * s),
        5.5 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFD9C685)
          ..strokeWidth = 1.2,
      );
    }
    return;
  }
  final d = _dir(p.toolAngle);
  final n = Offset(-d.dy, d.dx);
  Offset q(double along, double side) => hand + (d * along + n * side) * s;
  final handle = Paint()
    ..color = _woodLight
    ..strokeWidth = 2.1 * s
    ..strokeCap = StrokeCap.round;
  final metal = Paint()..color = const Color(0xFFB8C0C7);
  final edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.9
    ..color = const Color(0x88000000);
  void poly(List<Offset> pts, Paint fill) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final v in pts.skip(1)) {
      path.lineTo(v.dx, v.dy);
    }
    path.close();
    c
      ..drawPath(path, fill)
      ..drawPath(path, edge);
  }

  switch (tool) {
    case _Tool.axe:
      c.drawLine(q(-4, 0), q(16, 0), handle);
      poly(<Offset>[q(11, 0), q(16.5, 0), q(18, 6), q(12.5, 5)], metal);
    case _Tool.pick:
      c.drawLine(q(-4, 0), q(16, 0), handle);
      c.drawPath(
        Path()
          ..moveTo(q(12.5, -7).dx, q(12.5, -7).dy)
          ..quadraticBezierTo(
            q(16.5, 0).dx,
            q(16.5, 0).dy,
            q(12.5, 7.5).dx,
            q(12.5, 7.5).dy,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * s
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF8E98A2),
      );
    case _Tool.hoe:
      c.drawLine(q(-4, 0), q(17, 0), handle);
      poly(<Offset>[
        q(15, 0),
        q(18, 0),
        q(20, 7),
        q(15.5, 7),
      ], Paint()..color = const Color(0xFF8A7B66));
    case _Tool.hammer:
      c.drawLine(q(-3, 0), q(11, 0), handle);
      poly(<Offset>[
        q(8.5, -3.6),
        q(13, -3.6),
        q(13, 3.6),
        q(8.5, 3.6),
      ], Paint()..color = const Color(0xFF6A6A72));
    case _Tool.warHammer:
      c.drawLine(q(-4, 0), q(21, 0), handle);
      poly(<Offset>[
        q(16.5, -5),
        q(23, -5),
        q(23, 5),
        q(16.5, 5),
      ], Paint()..color = const Color(0xFF55555E));
    case _Tool.spear:
      c.drawLine(q(-6, 0), q(31, 0), handle);
      poly(<Offset>[q(30, -2), q(37, 0), q(30, 2)], metal);
    case _Tool.lance:
      c.drawLine(q(-6, 0), q(36, 0), handle);
      poly(<Offset>[q(35, -2), q(42, 0), q(35, 2)], metal);
      poly(<Offset>[q(30, 0), q(24, -1), q(26, -4.5)], Paint()..color = team);
    case _Tool.sword:
      poly(<Offset>[
        q(3, -1.2),
        q(19, -0.6),
        q(21, 0),
        q(19, 0.6),
        q(3, 1.2),
      ], metal);
      c.drawLine(
        q(2.4, -3.6),
        q(2.4, 3.6),
        Paint()
          ..color = const Color(0xFF6B4423)
          ..strokeWidth = 1.8 * s,
      );
      c.drawLine(q(-2, 0), q(2.4, 0), handle);
    case _Tool.staff:
      c.drawLine(
        q(-6, 0),
        q(32, 0),
        Paint()
          ..color = _heroAccent(def.id)
          ..strokeWidth = 2.2 * s
          ..strokeCap = StrokeCap.round,
      );
      c.drawCircle(q(34, 0), 3 * s, Paint()..color = const Color(0xFFFFFFFF));
      c.drawCircle(
        q(34, 0),
        3 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _heroAccent(def.id),
      );
    case _Tool.bow:
    case _Tool.net:
    case _Tool.none:
      break;
  }
}

void _bow(Canvas c, Offset grip, double s, _Pose p) {
  final bowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = _wood
    ..strokeWidth = 2 * s
    ..strokeCap = StrokeCap.round;
  final bend = 1.0 + (p.pull < 0 ? 0 : p.pull * 3.2);
  final top = grip.translate(-bend * s, -11 * s);
  final bottom = grip.translate(-bend * s, 11 * s);
  final path = Path()
    ..moveTo(top.dx, top.dy)
    ..quadraticBezierTo(grip.dx + 7 * s, grip.dy, bottom.dx, bottom.dy);
  c.drawPath(path, bowPaint);
  final string = Paint()
    ..color = const Color(0xDDFFFFFF)
    ..strokeWidth = 0.8;
  if (p.pull >= 0) {
    final pullPt = grip.translate(-p.pull * 10 * s, 0);
    c
      ..drawLine(top, pullPt, string)
      ..drawLine(pullPt, bottom, string);
    if (p.arrow) {
      c
        ..drawLine(
          pullPt,
          grip.translate(9 * s, 0),
          Paint()
            ..color = const Color(0xFFD9C685)
            ..strokeWidth = 1.3 * s,
        )
        ..drawPath(
          Path()
            ..moveTo(grip.dx + 9 * s, grip.dy - 1.8 * s)
            ..lineTo(grip.dx + 12 * s, grip.dy)
            ..lineTo(grip.dx + 9 * s, grip.dy + 1.8 * s)
            ..close(),
          Paint()..color = _steel,
        );
    }
  } else {
    c.drawLine(top, bottom, string);
  }
}

// ───────────────────────── Effets d'impact ─────────────────────────

void _drawFx(Canvas c, Offset o, double s, _Pose p, SpriteContext ctx) {
  final t = p.impact;
  if (t == null || p.fx == _Fx.none) return;
  final at = o + p.fxAt * s;
  final fade = (1 - t).clamp(0.0, 1.0);
  switch (p.fx) {
    case _Fx.chips:
      for (var i = 0; i < 6; i++) {
        final ang = -0.3 - i * 0.5;
        final v = 9.0 + i * 1.6;
        final pos = at.translate(
          math.cos(ang) * v * t * s,
          (math.sin(ang) * v * t + 22 * t * t) * s,
        );
        c.drawRect(
          Rect.fromCenter(center: pos, width: 2.6 * s, height: 1.5 * s),
          Paint()
            ..color =
                (i.isEven ? const Color(0xFFD9B27A) : const Color(0xFF8A6238))
                    .withValues(alpha: fade),
        );
      }
    case _Fx.sparkStone:
    case _Fx.sparkIron:
    case _Fx.sparkGold:
      final col = switch (p.fx) {
        _Fx.sparkGold => const Color(0xFFFFD35A),
        _Fx.sparkIron => const Color(0xFFBFE3FF),
        _ => const Color(0xFFEDEDED),
      };
      if (t < 0.35) {
        c.drawCircle(
          at,
          (3.2 - t * 6) * s,
          Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9),
        );
      }
      for (var i = 0; i < 7; i++) {
        final ang = -0.15 - i * 0.42;
        final v0 = (2 + t * 9) * s;
        c.drawLine(
          at + Offset(math.cos(ang), math.sin(ang)) * v0,
          at + Offset(math.cos(ang), math.sin(ang)) * (v0 + 3.2 * s),
          Paint()
            ..color = col.withValues(alpha: fade)
            ..strokeWidth = 1.3
            ..strokeCap = StrokeCap.round,
        );
      }
    case _Fx.dust:
      for (var i = -1; i <= 1; i++) {
        c.drawCircle(
          at.translate(i * 5 * t * s, -t * 5 * s),
          (1.8 + t * 4.5) * s,
          Paint()
            ..color = const Color(0xFFB9A27A).withValues(alpha: 0.5 * fade),
        );
      }
    case _Fx.hit:
      c.drawCircle(
        at,
        (2 + t * 4) * s,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7 * fade),
      );
      for (var i = 0; i < 4; i++) {
        final ang = -0.8 + i * 0.55;
        c.drawLine(
          at + Offset(math.cos(ang), math.sin(ang)) * (2 * s),
          at + Offset(math.cos(ang), math.sin(ang)) * ((3 + t * 8) * s),
          Paint()
            ..color = const Color(0xFFFFD6B0).withValues(alpha: fade)
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round,
        );
      }
    case _Fx.none:
      break;
  }
}

// ───────────────────────── Cheval, catapulte, corbeau ─────────────────────────

void _horse(Canvas c, Offset a, double s, SpriteContext ctx) {
  final moving = ctx.action == UnitAction.walk;
  final ph = moving ? _fract(ctx.time * 1.9 + ctx.seed * 0.11) : 0.0;
  final bob = moving
      ? -math.sin(ph * _tau * 2).abs() * 1.6
      : math.sin(ctx.time * 1.5 + ctx.seed) * 0.3;
  final coat = <Color>[
    const Color(0xFF7A5230),
    const Color(0xFF4A3322),
    const Color(0xFFB7A58A),
    const Color(0xFF2E2622),
  ][ctx.seed.abs() % 4];
  final horse = Paint()..color = coat;
  final dark = Paint()
    ..color = Color.lerp(coat, const Color(0xFF000000), 0.35)!
    ..strokeWidth = 2.4 * s
    ..strokeCap = StrokeCap.round;

  // Pattes : paires avant / arrière en décalage.
  void leg(double x, double off) {
    final sw = moving ? math.sin((ph + off) * _tau) * 5 : 0.0;
    final lf = moving
        ? math.max<double>(0, math.cos((ph + off) * _tau)) * 3
        : 0.0;
    c.drawLine(
      a.translate(x * s, -6 * s + bob * s),
      a.translate((x + sw) * s, -lf * s),
      dark,
    );
  }

  leg(-9, 0.5);
  leg(-5, 0.62);
  c
    // Queue.
    ..drawPath(
      Path()
        ..moveTo(a.dx - 14 * s, a.dy - 12 * s + bob * s)
        ..quadraticBezierTo(
          a.dx - 20 * s,
          a.dy -
              8 * s +
              math.sin(ctx.time * 6 + ctx.seed) * (moving ? 2.5 : 0.8) * s,
          a.dx - 18 * s,
          a.dy - 2 * s,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * s
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(coat, const Color(0xFF000000), 0.5)!,
    )
    // Corps.
    ..drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: a.translate(0, -10 * s + bob * s),
          width: 30 * s,
          height: 14 * s,
        ),
        Radius.circular(7 * s),
      ),
      horse,
    )
    // Encolure et tête.
    ..drawPath(
      Path()
        ..moveTo(a.dx + 10 * s, a.dy - 14 * s + bob * s)
        ..lineTo(a.dx + 19 * s, a.dy - 25 * s + bob * s)
        ..lineTo(a.dx + 24 * s, a.dy - 22 * s + bob * s)
        ..lineTo(a.dx + 14 * s, a.dy - 8 * s + bob * s)
        ..close(),
      horse,
    )
    ..drawCircle(
      a.translate(21 * s, -23 * s + bob * s),
      0.8 * s,
      Paint()..color = const Color(0xFF120D0A),
    )
    // Crinière.
    ..drawLine(
      a.translate(11 * s, -15 * s + bob * s),
      a.translate(19 * s, -26 * s + bob * s),
      dark..strokeWidth = 2.6 * s,
    )
    // Couverture de selle aux couleurs de l'équipe.
    ..drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: a.translate(1 * s, -15.5 * s + bob * s),
          width: 13 * s,
          height: 4 * s,
        ),
        Radius.circular(1.6 * s),
      ),
      Paint()..color = teamColor(ctx.team),
    );
  dark.strokeWidth = 2.4 * s;
  leg(7, 0);
  leg(12, 0.12);
}

void _catapult(Canvas c, Offset a, double s, Paint body, SpriteContext ctx) {
  final wood = Paint()..color = const Color(0xFF8A6238);
  final dark = Paint()..color = const Color(0xFF55391C);
  // Châssis.
  c
    ..drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: a.translate(0, -9 * s),
          width: 34 * s,
          height: 10 * s,
        ),
        Radius.circular(2 * s),
      ),
      wood,
    )
    ..drawRect(
      Rect.fromCenter(
        center: a.translate(0, -12 * s),
        width: 34 * s,
        height: 3 * s,
      ),
      body,
    );
  // Roues qui tournent en marche.
  final roll = ctx.action == UnitAction.walk ? ctx.time * 7 : 0.0;
  for (final dx in <double>[-12, 12]) {
    final at = a.translate(dx * s, -4 * s);
    c
      ..drawCircle(at, 6 * s, dark)
      ..drawCircle(at, 2.2 * s, wood)
      ..drawLine(
        at,
        at.translate(math.cos(roll) * 5.4 * s, math.sin(roll) * 5.4 * s),
        Paint()
          ..color = wood.color
          ..strokeWidth = 1.2 * s,
      );
  }
  // Bras : armé lentement, lâché d'un coup.
  var ang = 0.63;
  if (ctx.action == UnitAction.shoot) {
    final ph = _fract(ctx.time * 0.5 + ctx.seed * 0.1);
    ang = ph < 0.7
        ? _mix(0.63, -0.95, _ease(ph / 0.7))
        : (ph < 0.78
              ? _mix(-0.95, 1.3, _ease((ph - 0.7) / 0.08))
              : _mix(1.3, 0.63, _ease((ph - 0.78) / 0.22)));
  }
  final pivot = a.translate(-4 * s, -11 * s);
  final tip = pivot + _dir(ang) * (23.6 * s);
  c
    ..drawLine(
      pivot,
      tip,
      Paint()
        ..color = const Color(0xFF6B4423)
        ..strokeWidth = 3 * s
        ..strokeCap = StrokeCap.round,
    )
    ..drawCircle(tip, 4.5 * s, Paint()..color = const Color(0xFF4A4A4A));
}

void _raven(Canvas c, Offset a, double s, Paint body, SpriteContext ctx) {
  final flap =
      math.sin(ctx.time * (ctx.action == UnitAction.walk ? 20 : 7) + ctx.seed) *
      4 *
      s;
  final dark = Paint()..color = const Color(0xFF1E1A26);
  c
    ..drawOval(
      Rect.fromCenter(
        center: a.translate(0, -16 * s),
        width: 14 * s,
        height: 20 * s,
      ),
      dark,
    )
    ..drawPath(
      Path()
        ..moveTo(a.dx - 3 * s, a.dy - 18 * s)
        ..lineTo(a.dx - 18 * s, a.dy - 24 * s - flap)
        ..lineTo(a.dx - 5 * s, a.dy - 10 * s)
        ..close(),
      dark,
    )
    ..drawPath(
      Path()
        ..moveTo(a.dx + 3 * s, a.dy - 18 * s)
        ..lineTo(a.dx + 18 * s, a.dy - 24 * s - flap)
        ..lineTo(a.dx + 5 * s, a.dy - 10 * s)
        ..close(),
      dark,
    )
    ..drawCircle(a.translate(0, -27 * s), 4.5 * s, dark)
    ..drawPath(
      Path()
        ..moveTo(a.dx + 3 * s, a.dy - 27 * s)
        ..lineTo(a.dx + 9 * s, a.dy - 26 * s)
        ..lineTo(a.dx + 3 * s, a.dy - 24 * s)
        ..close(),
      Paint()..color = const Color(0xFFE6B422),
    )
    // Bandeau de l'équipe.
    ..drawRect(
      Rect.fromCenter(
        center: a.translate(0, -14 * s),
        width: 11 * s,
        height: 3 * s,
      ),
      body,
    );
}
