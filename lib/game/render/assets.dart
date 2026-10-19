import 'dart:ui';

import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/render/building_art.dart';
import 'package:age_of_empire_camer/game/render/unit_art.dart';
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

/// Geste d'une unité, déduit de l'état réel de la simulation (rendu seul).
enum UnitAction {
  idle,
  walk,
  chop,
  forage,
  mine,
  farm,
  hunt,
  build,
  melee,
  shoot,
}

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
    this.action = UnitAction.idle,
    this.faceRight = true,
    this.faceDown = true,
    this.carry = -1,
  });

  /// Geste en cours (récolte, construction, combat…).
  final UnitAction action;

  /// Orientation à l'écran : l'unité est dessinée tournée vers +x puis
  /// retournée si besoin ; [faceDown] = de face (visage visible).
  final bool faceRight;
  final bool faceDown;

  /// Ressource portée (-1 : rien) ; pendant un geste de récolte, ressource récoltée.
  final int carry;

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
      r.register('unit/${u.id}', unitArt(u));
    }
    for (final b in defs.buildings) {
      r.register('building/${b.id}', buildingArt(b.id, field: b.isField));
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
