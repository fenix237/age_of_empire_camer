import 'dart:math' as math;
import 'dart:ui';

import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';

/// Échelle des sprites d'unités (les placeholders sont dessinés à 1×).
const double unitScale = 1.7;

/// Couleurs des joueurs (daltonisme : formes distinctes en plus, voir Phase 9).
const List<Color> teamColors = <Color>[
  Color(0xFF2E7BD6), // bleu
  Color(0xFFD64545), // rouge
  Color(0xFF3FA34D), // vert
  Color(0xFFE0B72B), // jaune
  Color(0xFF8E4FC9), // violet
  Color(0xFF1FB5B0), // turquoise
  Color(0xFFE07B2B), // orange
  Color(0xFFD65FA8), // rose
];

Color teamColor(int owner) => teamColors[owner % teamColors.length];

/// Dessine un sprite : ancre = point au sol (pieds / coin bas du losange).
typedef SpriteDrawer =
    void Function(
      Canvas canvas,
      Offset anchor,
      SpriteContext ctx,
    );

/// Paramètres d'un dessin de sprite.
class SpriteContext {
  const SpriteContext({
    this.team = 0,
    this.scale = 1,
    this.time = 0,
    this.moving = false,
    this.progress = 1,
    this.footprintW = 1,
    this.footprintH = 1,
    this.seed = 0,
    this.flash = false,
  });

  final int team;
  final double scale;

  /// Temps en secondes (animation minimale).
  final double time;
  final bool moving;

  /// Avancement de construction 0..1 (bâtiments).
  final double progress;
  final int footprintW;
  final int footprintH;

  /// Graine de variation stable (arbres, herbe).
  final int seed;
  final bool flash;
}

/// Registre « clé → sprite » : on remplace les placeholders par de vrais
/// assets sans toucher au code de rendu (Analyse §12.1).
///
/// Clés : `terrain/<id>`, `unit/<id>`, `building/<id>`, `resource/<id>`.
class AssetRegistry {
  AssetRegistry();

  /// Registre peuplé de placeholders pour toutes les définitions du jeu.
  factory AssetRegistry.placeholders(Defs defs) {
    final r = AssetRegistry();
    for (final u in defs.units) {
      r.register('unit/${u.id}', _unitArt(u.id, u.villager));
    }
    for (final b in defs.buildings) {
      r.register('building/${b.id}', _buildingArt(b.id, b.isField));
    }
    for (final n in defs.resources) {
      r.register('resource/${n.id}', _resourceArt(n.id));
    }
    for (final t in defs.terrain) {
      r.register('terrain/${t.id}', _terrainArt(t.id));
    }
    return r;
  }

  final Map<String, SpriteDrawer> _drawers = <String, SpriteDrawer>{};
  final Set<String> _missing = <String>{};

  /// Sprites statiques (ressources) enregistrés une fois en `Picture`, par
  /// clé puis par variante : un arbre coûte une seule commande de dessin.
  final Map<String, List<Picture?>> _pictures = <String, List<Picture?>>{};
  static const int _variants = 8;

  /// Libère les images en cache.
  void dispose() {
    for (final list in _pictures.values) {
      for (final p in list) {
        p?.dispose();
      }
    }
    _pictures.clear();
  }

  /// Clés demandées mais absentes (test de complétude des assets).
  Set<String> get missing => Set<String>.unmodifiable(_missing);

  Iterable<String> get keys => _drawers.keys;

  void register(String key, SpriteDrawer drawer) => _drawers[key] = drawer;

  bool has(String key) => _drawers.containsKey(key);

  void draw(String key, Canvas canvas, Offset anchor, SpriteContext ctx) {
    final d = _drawers[key];
    if (d == null) {
      _missing.add(key);
      _drawMissing(canvas, anchor);
      return;
    }
    if (key.startsWith('resource/')) {
      _drawCached(key, d, canvas, anchor, ctx);
    } else {
      d(canvas, anchor, ctx);
    }
  }

  void _drawCached(
    String key,
    SpriteDrawer d,
    Canvas canvas,
    Offset anchor,
    SpriteContext ctx,
  ) {
    final list = _pictures[key] ??= List<Picture?>.filled(_variants, null);
    final v = ctx.seed.abs() % _variants;
    var pic = list[v];
    if (pic == null) {
      final rec = PictureRecorder();
      d(Canvas(rec), Offset.zero, SpriteContext(seed: v));
      pic = list[v] = rec.endRecording();
    }
    canvas
      ..save()
      ..translate(anchor.dx, anchor.dy)
      ..drawPicture(pic)
      ..restore();
  }

  static void _drawMissing(Canvas c, Offset a) {
    c.drawRect(
      Rect.fromCenter(center: a.translate(0, -12), width: 24, height: 24),
      Paint()..color = const Color(0xFFFF00FF),
    );
  }
}

// ───────────────────────── Terrain ─────────────────────────

const Map<String, Color> terrainColors = <String, Color>{
  'grass': Color(0xFF5E9C45),
  'dirt': Color(0xFF8C6A45),
  'sand': Color(0xFFD9C685),
  'savanna': Color(0xFFB4A850),
  'shallow': Color(0xFF4FA3C7),
  'deep': Color(0xFF1F5F9A),
  'mountain': Color(0xFF737373),
  'road': Color(0xFFA68E6A),
  'marsh': Color(0xFF55785A),
  'cliff': Color(0xFF5C5148),
};

SpriteDrawer _terrainArt(String id) {
  final base = terrainColors[id] ?? const Color(0xFFFF00FF);
  return (Canvas c, Offset a, SpriteContext ctx) {
    final v = ((ctx.seed * 2654435761) >> 7) & 0xF;
    final shade = (v - 8) * 1.5;
    final col = Color.fromARGB(
      255,
      (base.r * 255 + shade).round().clamp(0, 255),
      (base.g * 255 + shade).round().clamp(0, 255),
      (base.b * 255 + shade).round().clamp(0, 255),
    );
    final p = Path()
      ..moveTo(a.dx, a.dy - Iso.halfH * 2 + 0)
      ..lineTo(a.dx + Iso.halfW, a.dy - Iso.halfH)
      ..lineTo(a.dx, a.dy)
      ..lineTo(a.dx - Iso.halfW, a.dy - Iso.halfH)
      ..close();
    c.drawPath(p, Paint()..color = col);
  };
}

// ───────────────────────── Unités ─────────────────────────

SpriteDrawer _unitArt(String id, bool villager) => (c, a, ctx) {
  final team = teamColor(ctx.team);
  final bob = ctx.moving ? math.sin(ctx.time * 12 + ctx.seed) * 1.5 : 0.0;
  final s = ctx.scale;
  // Ombre.
  c.drawOval(
    Rect.fromCenter(center: a, width: 26 * s, height: 11 * s),
    Paint()..color = const Color(0x55000000),
  );
  final body = Paint()..color = ctx.flash ? const Color(0xFFFFFFFF) : team;
  final bodyRect = Rect.fromCenter(
    center: a.translate(0, -12 * s + bob),
    width: (villager ? 13 : 16) * s,
    height: 20 * s,
  );
  if (villager) {
    c.drawOval(bodyRect, body);
  } else if (id == 'horseman') {
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: a.translate(0, -11 * s + bob),
          width: 28 * s,
          height: 16 * s,
        ),
        Radius.circular(6 * s),
      ),
      body,
    );
  } else {
    c.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(3 * s)),
      body,
    );
  }
  // Tête.
  c.drawCircle(
    a.translate(0, -25 * s + bob),
    5 * s,
    Paint()..color = const Color(0xFFE8C9A0),
  );
  // Arme / outil selon le type.
  final line = Paint()
    ..color = const Color(0xFF3B2A1A)
    ..strokeWidth = 2 * s;
  switch (id) {
    case 'spearman':
      c.drawLine(a.translate(8 * s, -4 * s), a.translate(8 * s, -34 * s), line);
    case 'archer':
      c.drawArc(
        Rect.fromCenter(
          center: a.translate(9 * s, -14 * s),
          width: 10 * s,
          height: 20 * s,
        ),
        -math.pi / 2,
        math.pi,
        false,
        line..style = PaintingStyle.stroke,
      );
    case 'iron_warrior':
      c.drawRect(
        Rect.fromCenter(
          center: a.translate(-9 * s, -13 * s),
          width: 6 * s,
          height: 14 * s,
        ),
        Paint()..color = const Color(0xFF9AA3AB),
      );
    case 'villager':
      c.drawLine(
        a.translate(7 * s, -6 * s),
        a.translate(11 * s, -18 * s),
        line,
      );
  }
};

// ───────────────────────── Bâtiments ─────────────────────────

SpriteDrawer _buildingArt(String id, bool field) => (c, a, ctx) {
  // [a] : coin bas du losange de l'emprise. On redessine à partir du
  // centre de l'emprise pour rester symétrique.
  final w = ctx.footprintW.toDouble();
  final h = ctx.footprintH.toDouble();
  // Sommets de l'emprise relatifs au coin bas (0,0) : haut = -(w+h)*halfH.
  final bottom = a;
  final right = a.translate(w * Iso.halfW, -w * Iso.halfH);
  final left = a.translate(-h * Iso.halfW, -h * Iso.halfH);
  final top = a.translate((w - h) * Iso.halfW, -(w + h) * Iso.halfH);
  final team = teamColor(ctx.team);
  if (field) {
    final path = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    c.drawPath(path, Paint()..color = const Color(0xFF7A5A2E));
    // Sillons.
    final f = Paint()
      ..color = const Color(0xFF9CB84A)
      ..strokeWidth = 2;
    for (var i = 1; i < ctx.footprintW * 2; i++) {
      final t = i / (ctx.footprintW * 2);
      c.drawLine(
        Offset.lerp(top, left, t)!,
        Offset.lerp(right, bottom, t)!,
        f,
      );
    }
    return;
  }
  final prog = ctx.progress.clamp(0.05, 1.0);
  final height = (22.0 + (w + h) * 9) * prog;
  final up = Offset(0, -height);
  final wallL = Path()
    ..moveTo(left.dx, left.dy)
    ..lineTo(bottom.dx, bottom.dy)
    ..lineTo(bottom.dx + up.dx, bottom.dy + up.dy)
    ..lineTo(left.dx + up.dx, left.dy + up.dy)
    ..close();
  final wallR = Path()
    ..moveTo(bottom.dx, bottom.dy)
    ..lineTo(right.dx, right.dy)
    ..lineTo(right.dx + up.dx, right.dy + up.dy)
    ..lineTo(bottom.dx + up.dx, bottom.dy + up.dy)
    ..close();
  final roof = Path()
    ..moveTo(top.dx + up.dx, top.dy + up.dy)
    ..lineTo(right.dx + up.dx, right.dy + up.dy)
    ..lineTo(bottom.dx + up.dx, bottom.dy + up.dy)
    ..lineTo(left.dx + up.dx, left.dy + up.dy)
    ..close();
  final base = _buildingBase(id);
  final alpha = ctx.progress < 1 ? 0.7 : 1.0;
  c
    ..drawPath(
      wallL,
      Paint()..color = _shade(base, 0.78).withValues(alpha: alpha),
    )
    ..drawPath(
      wallR,
      Paint()..color = _shade(base, 0.62).withValues(alpha: alpha),
    )
    ..drawPath(
      roof,
      Paint()..color = _shade(team, 0.95).withValues(alpha: alpha),
    )
    ..drawPath(
      roof,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x66000000)
        ..strokeWidth = 1.2,
    );
  if (ctx.progress < 1) {
    // Échafaudage : montants aux angles.
    final p = Paint()
      ..color = const Color(0xFF5C3B1B)
      ..strokeWidth = 2;
    for (final v in <Offset>[left, right, bottom, top]) {
      c.drawLine(v, v.translate(0, -height - 8), p);
    }
  }
};

Color _buildingBase(String id) => switch (id) {
  'town_center' => const Color(0xFFB9825A),
  'hut' => const Color(0xFFC89B6A),
  'barracks' => const Color(0xFF8A5A44),
  'forge' => const Color(0xFF6E6E78),
  'market' => const Color(0xFFC2A24F),
  'granary' => const Color(0xFFB8A66A),
  'lumber_camp' => const Color(0xFF7C5A33),
  'mining_camp' => const Color(0xFF7A7A6E),
  _ => const Color(0xFFAA8866),
};

Color _shade(Color c, double f) => Color.from(
  alpha: c.a,
  red: (c.r * f).clamp(0, 1),
  green: (c.g * f).clamp(0, 1),
  blue: (c.b * f).clamp(0, 1),
);

// ───────────────────────── Ressources ─────────────────────────

SpriteDrawer _resourceArt(String id) => (c, a, ctx) {
  final r = ((ctx.seed * 2654435761) >> 5) & 0xFF;
  switch (id) {
    case 'tree':
      final h = 34 + (r % 14).toDouble();
      c
        ..drawOval(
          Rect.fromCenter(center: a, width: 28, height: 12),
          Paint()..color = const Color(0x44000000),
        )
        ..drawRect(
          Rect.fromCenter(center: a.translate(0, -8), width: 6, height: 16),
          Paint()..color = const Color(0xFF5A3A1E),
        );
      final crown = Path()
        ..moveTo(a.dx, a.dy - h - 6)
        ..lineTo(a.dx + 17, a.dy - 12)
        ..lineTo(a.dx - 17, a.dy - 12)
        ..close();
      c.drawPath(crown, Paint()..color = const Color(0xFF2F6B35));
    case 'berries':
      c.drawOval(
        Rect.fromCenter(center: a.translate(0, -7), width: 34, height: 18),
        Paint()..color = const Color(0xFF3D7D3A),
      );
      final dot = Paint()..color = const Color(0xFFC83A56);
      for (var i = 0; i < 5; i++) {
        c.drawCircle(
          a.translate(-10.0 + i * 5 + (r % 3), -8 - (i % 2) * 4),
          2.4,
          dot,
        );
      }
    case 'game':
      c
        ..drawOval(
          Rect.fromCenter(center: a.translate(0, -9), width: 30, height: 15),
          Paint()..color = const Color(0xFFB5895A),
        )
        ..drawCircle(
          a.translate(13, -14),
          5,
          Paint()..color = const Color(0xFFB5895A),
        );
    default:
      final col = switch (id) {
        'quarry' => const Color(0xFF9B9B9B),
        'iron_mine' => const Color(0xFF5E6B7A),
        'gold_mine' => const Color(0xFFE6B422),
        _ => const Color(0xFFFF00FF),
      };
      final p = Path()
        ..moveTo(a.dx - 18, a.dy)
        ..lineTo(a.dx - 10, a.dy - 22)
        ..lineTo(a.dx + 2, a.dy - 14)
        ..lineTo(a.dx + 12, a.dy - 26)
        ..lineTo(a.dx + 20, a.dy)
        ..close();
      c
        ..drawPath(p, Paint()..color = col)
        ..drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0x55000000),
        );
  }
};

/// Couleur d'une ressource pour l'interface et la mini-carte.
Color resourceColor(Res r) => switch (r) {
  Res.food => const Color(0xFFD35D5D),
  Res.wood => const Color(0xFF8B5A2B),
  Res.stone => const Color(0xFF9B9B9B),
  Res.iron => const Color(0xFF6E8CA8),
  Res.gold => const Color(0xFFE6B422),
};
