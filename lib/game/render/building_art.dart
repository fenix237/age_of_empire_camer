import 'dart:math' as math;
import 'dart:ui';

import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/render/assets.dart';

/// Illustrations de bâtiments dessinées par le code (en attendant les vrais
/// atlas de la Phase 9) : volumes isométriques, toits de chaume, pierre,
/// détails propres à chaque bâtiment et bandeau à la couleur du joueur.

enum _Roof { flat, gable, cone, dome, crenel, none }

class _Spec {
  const _Spec({
    required this.wall,
    required this.roof,
    required this.roofKind,
    this.height,
    this.ridge = 0.5,
  });

  final Color wall;
  final Color roof;
  final _Roof roofKind;

  /// Hauteur des murs (px) ; null = proportionnelle à l'emprise.
  final double? height;

  /// Hauteur du faîtage, en fraction de la largeur de l'emprise.
  final double ridge;
}

const Color _thatch = Color(0xFFC9A347);
const Color _clay = Color(0xFFB9825A);
const Color _ochre = Color(0xFFC89B6A);
const Color _stone = Color(0xFF9A9A92);
const Color _darkStone = Color(0xFF6E6E78);

_Spec _specOf(String id) => switch (id) {
  'town_center' => const _Spec(
    wall: _clay,
    roof: _thatch,
    roofKind: _Roof.gable,
    height: 44,
    ridge: 0.42,
  ),
  'hut' => const _Spec(
    wall: _ochre,
    roof: _thatch,
    roofKind: _Roof.cone,
    height: 18,
    ridge: 0.9,
  ),
  'granary' => const _Spec(
    wall: Color(0xFFB8A66A),
    roof: _thatch,
    roofKind: _Roof.cone,
    height: 24,
    ridge: 0.8,
  ),
  'lumber_camp' => const _Spec(
    wall: Color(0xFF7C5A33),
    roof: Color(0xFF5E4326),
    roofKind: _Roof.gable,
    height: 14,
    ridge: 0.3,
  ),
  'mining_camp' => const _Spec(
    wall: Color(0xFF7A7A6E),
    roof: Color(0xFF5C5C54),
    roofKind: _Roof.gable,
    height: 14,
    ridge: 0.3,
  ),
  'barracks' => const _Spec(
    wall: Color(0xFF8A5A44),
    roof: _thatch,
    roofKind: _Roof.gable,
    height: 30,
    ridge: 0.4,
  ),
  'forge' => const _Spec(
    wall: _darkStone,
    roof: Color(0xFF55555E),
    roofKind: _Roof.gable,
    height: 28,
    ridge: 0.3,
  ),
  'market' => const _Spec(
    wall: Color(0xFFC2A24F),
    roof: Color(0xFFD04A3A),
    roofKind: _Roof.gable,
    height: 22,
    ridge: 0.28,
  ),
  'palace' => const _Spec(
    wall: Color(0xFFD8C8A8),
    roof: Color(0xFFE6B422),
    roofKind: _Roof.dome,
    height: 52,
    ridge: 0.7,
  ),
  'wall' => const _Spec(
    wall: _stone,
    roof: Color(0xFFB4B4AA),
    roofKind: _Roof.crenel,
    height: 20,
  ),
  'tower' => const _Spec(
    wall: _stone,
    roof: Color(0xFFB4B4AA),
    roofKind: _Roof.crenel,
    height: 64,
  ),
  'stable' => const _Spec(
    wall: Color(0xFF8E6B45),
    roof: _thatch,
    roofKind: _Roof.gable,
    height: 26,
    ridge: 0.36,
  ),
  'siege_workshop' => const _Spec(
    wall: Color(0xFF6B5638),
    roof: Color(0xFF5E4326),
    roofKind: _Roof.gable,
    height: 30,
    ridge: 0.34,
  ),
  'altar' => const _Spec(
    wall: Color(0xFFCFC7B6),
    roof: Color(0xFFE8E0D0),
    roofKind: _Roof.flat,
    height: 12,
  ),
  'fortress' => const _Spec(
    wall: Color(0xFF8A8A82),
    roof: Color(0xFFB4B4AA),
    roofKind: _Roof.crenel,
    height: 72,
  ),
  _ => const _Spec(
    wall: Color(0xFFAA8866),
    roof: _thatch,
    roofKind: _Roof.gable,
  ),
};

Color _shade(Color c, double f) => Color.from(
  alpha: c.a,
  red: (c.r * f).clamp(0, 1),
  green: (c.g * f).clamp(0, 1),
  blue: (c.b * f).clamp(0, 1),
);

Path _poly(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final o in pts.skip(1)) {
    p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

/// Dessin d'un bâtiment (ou d'un champ). Ancre = coin bas de l'emprise.
SpriteDrawer buildingArt(String id, {required bool field}) => (c, a, ctx) {
  final w = ctx.footprintW.toDouble();
  final h = ctx.footprintH.toDouble();
  final bottom = a;
  final right = a.translate(w * Iso.halfW, -w * Iso.halfH);
  final left = a.translate(-h * Iso.halfW, -h * Iso.halfH);
  final top = a.translate((w - h) * Iso.halfW, -(w + h) * Iso.halfH);
  final team = teamColor(ctx.team);

  if (field) {
    _field(c, top, right, bottom, left, ctx);
    return;
  }
  final spec = _specOf(id);
  final prog = ctx.progress.clamp(0.05, 1.0);
  final baseH = spec.height ?? (22.0 + (w + h) * 9);
  final height = baseH * prog;
  Offset up(Offset p, [double extra = 0]) => p.translate(0, -(height + extra));
  final alpha = ctx.progress < 1 ? 0.72 : 1.0;
  Paint fill(Color col) => Paint()..color = col.withValues(alpha: alpha);

  // Ombre portée.
  c.drawPath(
    _poly(<Offset>[
      top.translate(8, 4),
      right.translate(10, 5),
      bottom.translate(4, 7),
      left.translate(-2, 5),
    ]),
    Paint()..color = const Color(0x33000000),
  );

  // Murs.
  final wallL = _poly(<Offset>[left, bottom, up(bottom), up(left)]);
  final wallR = _poly(<Offset>[bottom, right, up(right), up(bottom)]);
  c
    ..drawPath(wallL, fill(_shade(spec.wall, 0.82)))
    ..drawPath(wallR, fill(_shade(spec.wall, 0.62)));
  _wallDetails(c, id, left, bottom, right, height, w, h, alpha);

  // Corniche à la couleur du joueur.
  final band = math.min<double>(5, height * 0.18);
  c
    ..drawPath(
      _poly(<Offset>[
        up(left, -band),
        up(bottom, -band),
        up(bottom),
        up(left),
      ]),
      fill(_shade(team, 0.95)),
    )
    ..drawPath(
      _poly(<Offset>[
        up(bottom, -band),
        up(right, -band),
        up(right),
        up(bottom),
      ]),
      fill(_shade(team, 0.72)),
    );

  // Toit.
  final t = up(top);
  final r = up(right);
  final b = up(bottom);
  final l = up(left);
  final ridgeH = spec.ridge * math.min(w, h) * Iso.halfH * 2;
  switch (spec.roofKind) {
    case _Roof.flat:
      c
        ..drawPath(_poly(<Offset>[t, r, b, l]), fill(spec.roof))
        ..drawPath(
          _poly(<Offset>[t, r, b, l]),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0x55000000),
        );
    case _Roof.gable:
      _gable(c, t, r, b, l, ridgeH, spec, alpha);
    case _Roof.cone:
      _cone(c, t, r, b, l, ridgeH, spec, alpha);
    case _Roof.dome:
      _dome(c, t, r, b, l, ridgeH, spec, alpha);
    case _Roof.crenel:
      _crenel(c, t, r, b, l, spec, alpha, id);
    case _Roof.none:
      break;
  }

  if (ctx.progress >= 1) {
    _roofDetails(c, id, t, r, b, l, ridgeH, w, h, team, ctx.time);
  } else {
    // Échafaudage : montants et traverses aux angles.
    final p = Paint()
      ..color = const Color(0xFF5C3B1B)
      ..strokeWidth = 2;
    for (final v in <Offset>[left, right, bottom, top]) {
      c.drawLine(v, v.translate(0, -height - 10), p);
    }
    c
      ..drawLine(up(left, 6), up(bottom, 6), p)
      ..drawLine(up(bottom, 6), up(right, 6), p);
  }
};

void _field(
  Canvas c,
  Offset top,
  Offset right,
  Offset bottom,
  Offset left,
  SpriteContext ctx,
) {
  c.drawPath(
    _poly(<Offset>[top, right, bottom, left]),
    Paint()..color = const Color(0xFF7A5A2E),
  );
  final f = Paint()
    ..color = const Color(0xFF9CB84A)
    ..strokeWidth = 2;
  final furrow = Paint()
    ..color = const Color(0xFF5C4222)
    ..strokeWidth = 1;
  for (var i = 1; i < ctx.footprintW * 2; i++) {
    final t = i / (ctx.footprintW * 2);
    final p0 = Offset.lerp(top, left, t)!;
    final p1 = Offset.lerp(right, bottom, t)!;
    c
      ..drawLine(p0, p1, i.isEven ? f : furrow)
      ..drawLine(p0, p1, furrow);
    if (i.isEven) continue;
    // Épis qui ondulent au vent le long du sillon.
    final tuft = Paint()
      ..color = const Color(0xFFD8C25A)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final n = ctx.footprintH * 2;
    for (var k = 0; k < n; k++) {
      final at = Offset.lerp(p0, p1, (k + 0.5) / n)!;
      final sway = math.sin(ctx.time * 2.2 + at.dx * 0.08 + k) * 1.6;
      c.drawLine(at, at.translate(sway, -7), tuft);
    }
  }
}

void _gable(
  Canvas c,
  Offset t,
  Offset r,
  Offset b,
  Offset l,
  double ridge,
  _Spec spec,
  double alpha,
) {
  final m1 = Offset.lerp(l, t, 0.5)!.translate(0, -ridge);
  final m2 = Offset.lerp(b, r, 0.5)!.translate(0, -ridge);
  Paint fill(Color col) => Paint()..color = col.withValues(alpha: alpha);
  // Pan arrière puis pan avant, et pignon avant.
  c
    ..drawPath(_poly(<Offset>[m1, m2, r, t]), fill(_shade(spec.roof, 0.95)))
    ..drawPath(_poly(<Offset>[l, b, m2, m1]), fill(_shade(spec.roof, 0.78)))
    ..drawPath(_poly(<Offset>[b, r, m2]), fill(_shade(spec.wall, 0.7)));
  // Brins de chaume.
  final line = Paint()
    ..color = const Color(0x33000000)
    ..strokeWidth = 1;
  for (var i = 1; i < 6; i++) {
    final k = i / 6;
    c.drawLine(
      Offset.lerp(l, b, k)!,
      Offset.lerp(m1, m2, k)!,
      line,
    );
  }
  c
    ..drawLine(
      m1,
      m2,
      Paint()
        ..color = _shade(spec.roof, 0.55)
        ..strokeWidth = 2,
    )
    ..drawPath(
      _poly(<Offset>[l, b, m2, m1]),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x44000000),
    );
}

void _cone(
  Canvas c,
  Offset t,
  Offset r,
  Offset b,
  Offset l,
  double ridge,
  _Spec spec,
  double alpha,
) {
  final apex = Offset(
    (t.dx + r.dx + b.dx + l.dx) / 4,
    (t.dy + r.dy + b.dy + l.dy) / 4 - ridge,
  );
  Paint fill(Color col) => Paint()..color = col.withValues(alpha: alpha);
  c
    ..drawPath(_poly(<Offset>[t, l, apex]), fill(_shade(spec.roof, 0.9)))
    ..drawPath(_poly(<Offset>[t, r, apex]), fill(_shade(spec.roof, 1)))
    ..drawPath(_poly(<Offset>[l, b, apex]), fill(_shade(spec.roof, 0.82)))
    ..drawPath(_poly(<Offset>[b, r, apex]), fill(_shade(spec.roof, 0.66)));
  final line = Paint()
    ..color = const Color(0x33000000)
    ..strokeWidth = 1;
  for (final p in <Offset>[l, b, r]) {
    c.drawLine(p, apex, line);
  }
}

void _dome(
  Canvas c,
  Offset t,
  Offset r,
  Offset b,
  Offset l,
  double ridge,
  _Spec spec,
  double alpha,
) {
  // Base plate, puis dôme en arc.
  final cx = (t.dx + b.dx) / 2;
  final cy = (t.dy + b.dy) / 2;
  final rx = (r.dx - l.dx) / 2 * 0.62;
  final ry = (b.dy - t.dy) / 2 * 0.62;
  Paint fill(Color col) => Paint()..color = col.withValues(alpha: alpha);
  c
    ..drawPath(_poly(<Offset>[t, r, b, l]), fill(_shade(spec.wall, 0.9)))
    ..drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      fill(_shade(spec.roof, 0.7)),
    );
  final dome = Path()
    ..moveTo(cx - rx, cy)
    ..quadraticBezierTo(cx, cy - ridge * 1.9, cx + rx, cy)
    ..close();
  c
    ..drawPath(dome, fill(spec.roof))
    ..drawPath(
      dome,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x55000000),
    )
    ..drawLine(
      Offset(cx, cy - ridge * 0.95),
      Offset(cx, cy - ridge * 1.35),
      Paint()
        ..color = const Color(0xFF8A6A12)
        ..strokeWidth = 2,
    );
}

void _crenel(
  Canvas c,
  Offset t,
  Offset r,
  Offset b,
  Offset l,
  _Spec spec,
  double alpha,
  String id,
) {
  Paint fill(Color col) => Paint()..color = col.withValues(alpha: alpha);
  c
    ..drawPath(_poly(<Offset>[t, r, b, l]), fill(_shade(spec.roof, 0.88)))
    ..drawPath(
      _poly(<Offset>[t, r, b, l]),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x55000000),
    );
  // Créneaux le long des deux arêtes avant.
  final merlon = fill(_shade(spec.wall, 0.95));
  final merlonDark = fill(_shade(spec.wall, 0.66));
  void along(Offset p, Offset q, Paint paint) {
    final n = math.max(2, ((q - p).distance / 11).round());
    for (var i = 0; i < n; i++) {
      final f = (i + 0.5) / n;
      final m = Offset.lerp(p, q, f)!;
      c.drawRect(
        Rect.fromCenter(center: m.translate(0, -3), width: 6, height: 7),
        paint,
      );
    }
  }

  along(l, b, merlon);
  along(b, r, merlonDark);
}

void _wallDetails(
  Canvas c,
  String id,
  Offset left,
  Offset bottom,
  Offset right,
  double height,
  double w,
  double h,
  double alpha,
) {
  if (id == 'wall') return;
  final dark = Paint()..color = const Color(0xCC1E1208);
  // Porte sur la face droite (bottom→right).
  Offset onR(double f, double hf) => Offset.lerp(
    bottom,
    right,
    f,
  )!.translate(0, -height * hf);
  const doorW = 0.16;
  final doorH = id == 'hut' ? 0.55 : 0.5;
  final door = _poly(<Offset>[
    onR(0.5 - doorW, 0),
    onR(0.5 + doorW, 0),
    onR(0.5 + doorW, doorH),
    onR(0.5 - doorW, doorH),
  ]);
  if (id != 'tower' && id != 'altar' && id != 'siege_workshop') {
    c.drawPath(door, dark);
  }
  // Fenêtres / meurtrières sur la face gauche.
  Offset onL(double f, double hf) => Offset.lerp(
    left,
    bottom,
    f,
  )!.translate(0, -height * hf);
  void window(double f, double hf, double size) {
    c.drawPath(
      _poly(<Offset>[
        onL(f - 0.05, hf),
        onL(f + 0.05, hf),
        onL(f + 0.05, hf + size),
        onL(f - 0.05, hf + size),
      ]),
      dark,
    );
  }

  switch (id) {
    case 'tower':
      window(0.5, 0.6, 0.18);
      window(0.5, 0.25, 0.14);
    case 'fortress':
      for (var i = 1; i <= 3; i++) {
        window(i / 4, 0.55, 0.16);
      }
      c.drawPath(
        _poly(<Offset>[
          onR(0.36, 0),
          onR(0.64, 0),
          onR(0.64, 0.42),
          onR(0.36, 0.42),
        ]),
        dark,
      );
    case 'barracks':
    case 'stable':
    case 'town_center':
      window(0.28, 0.45, 0.22);
      window(0.72, 0.45, 0.22);
    case 'forge':
      c.drawPath(
        _poly(<Offset>[
          onR(0.18, 0),
          onR(0.42, 0),
          onR(0.42, 0.4),
          onR(0.18, 0.4),
        ]),
        Paint()..color = const Color(0xFFFF7A18),
      );
    case 'palace':
      for (var i = 1; i <= 4; i++) {
        window(i / 5, 0.45, 0.28);
      }
    default:
      break;
  }
}

void _roofDetails(
  Canvas c,
  String id,
  Offset t,
  Offset r,
  Offset b,
  Offset l,
  double ridge,
  double w,
  double h,
  Color team,
  double time,
) {
  final center = Offset((t.dx + b.dx) / 2, (t.dy + b.dy) / 2);

  /// Panache de fumée : trois volutes qui montent, grossissent et s'effacent.
  void smoke(Offset from, Color col) {
    for (var i = 0; i < 3; i++) {
      final ph = (time * 0.4 + i / 3) % 1.0;
      c.drawCircle(
        from.translate(math.sin(ph * 6 + i * 2) * 4 + ph * 6, -ph * 30),
        2 + ph * 5,
        Paint()..color = col.withValues(alpha: 0.4 * (1 - ph)),
      );
    }
  }

  void flag(Offset base, double poleH) {
    final top = base.translate(0, -poleH);
    final wave = math.sin(time * 5 + base.dx) * 2.2;
    c
      ..drawLine(
        base,
        top,
        Paint()
          ..color = const Color(0xFF3B2A1A)
          ..strokeWidth = 2,
      )
      ..drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..quadraticBezierTo(
            top.dx + 7,
            top.dy + 1 + wave,
            top.dx + 14,
            top.dy + 4 + wave * 0.6,
          )
          ..quadraticBezierTo(
            top.dx + 7,
            top.dy + 6 + wave,
            top.dx,
            top.dy + 9,
          )
          ..close(),
        Paint()..color = team,
      );
  }

  switch (id) {
    case 'town_center':
      flag(center.translate(0, -ridge * 0.6), 26);
      // Cheminée de la grande case.
      c.drawRect(
        Rect.fromCenter(
          center: center.translate(-14, -ridge * 0.5 - 4),
          width: 6,
          height: 12,
        ),
        Paint()..color = const Color(0xFF6B4A33),
      );
    case 'barracks':
      // Lances croisées au faîte.
      final p = Paint()
        ..color = const Color(0xFF3B2A1A)
        ..strokeWidth = 2;
      final m = center.translate(0, -ridge - 6);
      c
        ..drawLine(m.translate(-8, 8), m.translate(8, -8), p)
        ..drawLine(m.translate(8, 8), m.translate(-8, -8), p);
    case 'forge':
      c
        ..drawRect(
          Rect.fromCenter(
            center: center.translate(8, -ridge - 6),
            width: 8,
            height: 18,
          ),
          Paint()..color = const Color(0xFF3A3A40),
        )
        ..drawCircle(
          center.translate(-6, -ridge - 3),
          2.5 + math.sin(time * 14).abs() * 1.5,
          Paint()..color = const Color(0xAAFF7A1E),
        );
      smoke(center.translate(8, -ridge - 16), const Color(0xFF8E8E96));
    case 'market':
      // Auvent rayé.
      final stripe = Paint()..color = const Color(0xFFF2EBD8);
      for (var i = 0; i < 4; i++) {
        final f = (i + 0.5) / 4;
        final m = Offset.lerp(l, b, f)!;
        c.drawLine(m, m.translate(0, 9), stripe..strokeWidth = 4);
      }
    case 'tower':
    case 'fortress':
      flag(center.translate(0, -4), id == 'fortress' ? 24 : 18);
    case 'stable':
      c.drawCircle(
        center.translate(0, -ridge - 4),
        4,
        Paint()..color = const Color(0xFF3B2A1A),
      );
    case 'siege_workshop':
      final p = Paint()
        ..color = const Color(0xFF3B2A1A)
        ..strokeWidth = 3;
      final m = center.translate(0, -ridge - 4);
      c
        ..drawCircle(m, 8, p..style = PaintingStyle.stroke)
        ..drawLine(m.translate(-8, 0), m.translate(8, 0), p)
        ..drawLine(m.translate(0, -8), m.translate(0, 8), p);
    case 'altar':
      final flame = Path()
        ..moveTo(center.dx, center.dy - 22)
        ..quadraticBezierTo(
          center.dx + 7,
          center.dy - 10,
          center.dx,
          center.dy - 4,
        )
        ..quadraticBezierTo(
          center.dx - 7,
          center.dy - 10,
          center.dx,
          center.dy - 22,
        );
      final flick = 1 + math.sin(time * 13) * 0.1;
      c
        ..drawCircle(
          center.translate(0, -4),
          9,
          Paint()..color = const Color(0xFF8A8478),
        )
        ..save()
        ..translate(center.dx, center.dy - 4)
        ..scale(1, flick)
        ..translate(-center.dx, -(center.dy - 4))
        ..drawPath(flame, Paint()..color = const Color(0xFFFF9A2E))
        ..restore()
        ..drawCircle(
          center.translate(0, -10),
          2.5,
          Paint()..color = const Color(0xFFFFE066),
        );
    case 'hut':
      smoke(center.translate(0, -ridge - 4), const Color(0xFFE0E0E0));
    case 'palace':
      flag(center.translate(0, -ridge * 1.4), 18);
    default:
      break;
  }
}
