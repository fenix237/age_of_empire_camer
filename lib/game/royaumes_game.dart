import 'dart:ui';

import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/input.dart';
import 'package:age_of_empire_camer/game/render/world_renderer.dart';
import 'package:age_of_empire_camer/sim/core/hashing.dart';
import 'package:flame/game.dart';

/// Hôte Flame du jeu : boucle de mise à jour/rendu, taille du canvas.
///
/// Le rendu isométrique est écrit sur mesure ([WorldRenderer]) plutôt que via
/// les composants iso génériques de Flame, pour contrôler le tri de
/// profondeur, le cache de terrain et les performances (Analyse §3.7).
class RoyaumesGame extends FlameGame {
  RoyaumesGame({
    required this.controller,
    required this.input,
    required this.panVelocity,
    this.onFps,
  });

  final GameController controller;
  final GameInput input;

  /// Vitesse de défilement caméra (clavier + bords), fournie par l'hôte.
  final Offset Function() panVelocity;
  final void Function(double fps)? onFps;

  double _fpsAcc = 0;
  int _fpsFrames = 0;
  double fps = 0;

  @override
  Color backgroundColor() => const Color(0xFF000000);

  @override
  void update(double dt) {
    super.update(dt);
    _fpsAcc += dt;
    _fpsFrames++;
    if (_fpsAcc >= 0.5) {
      fps = _fpsFrames / _fpsAcc;
      onFps?.call(fps);
      _fpsAcc = 0;
      _fpsFrames = 0;
    }
    controller.frame(dt, keyboardPan: panVelocity());
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final c = controller;
    c.renderer.paint(
      canvas,
      Size(size.x, size.y),
      c.camera,
      viewerId: c.localPlayer,
      selection: c.selection,
      alpha: c.loop.paused ? 1 : c.loop.alpha,
      time: c.time,
      markers: c.markers,
      ghost: c.ghost,
      debug: c.debug,
      fogEnabled: c.fogEnabled,
    );
    final r = input.selectionRect;
    if (r != null) paintSelectionRect(canvas, r);
    if (c.debug.stats) _stats(canvas);
  }

  void _stats(Canvas canvas) {
    final w = controller.world;
    final lines = <String>[
      'FPS ${fps.toStringAsFixed(0)}  tick ${w.tick}  x${controller.loop.speed}',
      'unités ${w.units.length}  bâtiments ${w.buildings.length}  ressources ${w.nodes.length}',
      'dessinés ${controller.renderer.entities.lastDrawn}  chemins ${w.paths.lastProcessed}/${w.pathQueue.length}',
      'zoom ${controller.camera.zoom.toStringAsFixed(2)}  blocs terrain ${controller.renderer.terrain.cachedChunks}',
      'hash ${w.hashLog.isEmpty ? '-' : hex64(w.hashLog.last)}',
    ];
    final builder = ParagraphBuilder(ParagraphStyle(fontSize: 12))
      ..pushStyle(
        TextStyle(
          color: const Color(0xFFFFFFFF),
          background: Paint()..color = const Color(0xAA000000),
        ),
      )
      ..addText(lines.join('\n'));
    final p = builder.build()..layout(const ParagraphConstraints(width: 520));
    canvas.drawParagraph(p, const Offset(8, 60));
  }
}
