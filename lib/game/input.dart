import 'dart:math' as math;
import 'dart:ui';

import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/game/selection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Traduit souris, clavier et toucher en actions du [GameController].
///
/// Souris : clic gauche = sélection / rectangle, clic droit = ordre contextuel,
/// molette = zoom, clic molette = glisser la carte, bords = défilement.
/// Tactile : appui = sélection puis destination, glisser = caméra (ou
/// rectangle en mode multi-sélection), pincement = zoom.
class GameInput {
  GameInput(this.controller, {this.onMenu});

  final GameController controller;

  /// Demande d'ouverture du menu pause (Échap).
  final VoidCallback? onMenu;

  // ── État commun ──
  /// Rectangle de sélection en cours (espace écran), ou null.
  Rect? selectionRect;
  Offset hover = Offset.zero;
  bool pointerInside = false;

  // ── Souris ──
  Offset? _downPos;
  int _downButtons = 0;
  bool _dragging = false;
  DateTime _lastClick = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastClickPos = Offset.zero;
  bool _middlePan = false;

  // ── Tactile ──
  final Map<int, Offset> _touches = <int, Offset>{};
  Offset? _touchStart;
  bool _touchMoved = false;
  double _pinchDist = 0;
  Offset _pinchCenter = Offset.zero;
  Offset _lastTouchDelta = Offset.zero;
  bool _wasPinching = false;

  // ── Clavier ──
  final Set<LogicalKeyboardKey> _held = <LogicalKeyboardKey>{};

  static const double dragSlopMouse = 6;
  static const double dragSlopTouch = 12;
  static const int doubleClickMs = 350;

  bool get _shift => HardwareKeyboard.instance.isShiftPressed;
  bool get _ctrl =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  GameController get c => controller;

  // ───────────────────────── Pointeurs ─────────────────────────

  void pointerDown(PointerDownEvent e) {
    hover = e.localPosition;
    pointerInside = true;
    if (e.kind == PointerDeviceKind.touch ||
        e.kind == PointerDeviceKind.stylus) {
      _touchDown(e);
      return;
    }
    _downPos = e.localPosition;
    _downButtons = e.buttons;
    _dragging = false;
    if (e.buttons & kMiddleMouseButton != 0) {
      _middlePan = true;
      return;
    }
    if (e.buttons & kSecondaryMouseButton != 0) {
      if (c.placing != null) {
        c.cancelPlacement();
      } else {
        c.orderAt(e.localPosition, queue: _shift);
      }
      return;
    }
    if (e.buttons & kPrimaryMouseButton != 0 && c.placing != null) {
      c.updateGhost(e.localPosition);
      c.confirmPlacement(keep: _shift);
      _downPos = null;
    }
  }

  void pointerMove(PointerMoveEvent e) {
    hover = e.localPosition;
    if (e.kind == PointerDeviceKind.touch ||
        e.kind == PointerDeviceKind.stylus) {
      _touchMove(e);
      return;
    }
    if (_middlePan) {
      c.camera.panByScreen(e.delta);
      return;
    }
    final down = _downPos;
    if (down == null || _downButtons & kPrimaryMouseButton == 0) return;
    if (!_dragging && (e.localPosition - down).distance > dragSlopMouse) {
      _dragging = true;
    }
    if (_dragging) selectionRect = Rect.fromPoints(down, e.localPosition);
  }

  void pointerUp(PointerUpEvent e) {
    if (e.kind == PointerDeviceKind.touch ||
        e.kind == PointerDeviceKind.stylus) {
      _touchUp(e);
      return;
    }
    if (_middlePan) {
      _middlePan = false;
      _downPos = null;
      return;
    }
    final down = _downPos;
    _downPos = null;
    if (down == null || _downButtons & kPrimaryMouseButton == 0) return;
    if (_dragging && selectionRect != null) {
      c.selectRect(selectionRect!, add: _shift);
    } else {
      final now = DateTime.now();
      final dbl =
          now.difference(_lastClick).inMilliseconds < doubleClickMs &&
          (e.localPosition - _lastClickPos).distance < dragSlopMouse;
      c.selectAt(e.localPosition, add: _shift, doubleClick: dbl);
      _lastClick = dbl ? DateTime.fromMillisecondsSinceEpoch(0) : now;
      _lastClickPos = e.localPosition;
    }
    selectionRect = null;
    _dragging = false;
  }

  void pointerCancel(PointerCancelEvent e) {
    _touches.remove(e.pointer);
    selectionRect = null;
    _dragging = false;
    _middlePan = false;
    _downPos = null;
  }

  void pointerHover(PointerHoverEvent e) {
    hover = e.localPosition;
    pointerInside = true;
    if (c.placing != null) c.updateGhost(e.localPosition);
  }

  void pointerExit() => pointerInside = false;

  void pointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final dy = e.scrollDelta.dy;
      if (dy == 0) return;
      c.camera.zoomAt(math.exp(-dy / 400), e.localPosition);
    }
  }

  /// Pincement / pan trackpad (Windows précision).
  void panZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (e.scale != 1) c.camera.zoomAt(e.scale, e.localPosition);
    c.camera.panByScreen(e.panDelta);
  }

  // ───────────────────────── Tactile ─────────────────────────

  void _touchDown(PointerDownEvent e) {
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 1) {
      _touchStart = e.localPosition;
      _touchMoved = false;
      _wasPinching = false;
      c.camera.velocity = Offset.zero;
    } else if (_touches.length == 2) {
      _beginPinch();
    }
  }

  void _beginPinch() {
    final pts = _touches.values.toList();
    _pinchDist = (pts[0] - pts[1]).distance;
    _pinchCenter = (pts[0] + pts[1]) / 2;
    _wasPinching = true;
    selectionRect = null;
  }

  void _touchMove(PointerMoveEvent e) {
    _touches[e.pointer] = e.localPosition;
    if (_touches.length >= 2) {
      final pts = _touches.values.toList();
      final d = (pts[0] - pts[1]).distance;
      final center = (pts[0] + pts[1]) / 2;
      if (_pinchDist > 0 && d > 0) {
        c.camera.zoomAt(d / _pinchDist, center);
      }
      c.camera.panByScreen(center - _pinchCenter);
      _pinchDist = d;
      _pinchCenter = center;
      _touchMoved = true;
      return;
    }
    final start = _touchStart;
    if (start == null) return;
    if (!_touchMoved && (e.localPosition - start).distance > dragSlopTouch) {
      _touchMoved = true;
    }
    if (!_touchMoved) return;
    if (c.placing != null) {
      c.updateGhost(e.localPosition);
    } else if (c.multiSelectMode) {
      selectionRect = Rect.fromPoints(start, e.localPosition);
    } else {
      c.camera.panByScreen(e.delta);
      _lastTouchDelta = e.delta;
    }
  }

  void _touchUp(PointerUpEvent e) {
    _touches.remove(e.pointer);
    if (_wasPinching) {
      if (_touches.isEmpty) _wasPinching = false;
      return;
    }
    final start = _touchStart;
    _touchStart = null;
    if (start == null) return;
    if (_touchMoved) {
      if (selectionRect != null) {
        c.selectRect(selectionRect!, add: true);
        selectionRect = null;
      } else if (c.placing == null) {
        c.camera.fling(_lastTouchDelta * 60);
      }
      return;
    }
    _tap(e.localPosition);
  }

  /// Appui court : sélectionner, ou donner l'ordre de destination.
  void _tap(Offset pos) {
    if (c.placing != null) {
      c.updateGhost(pos);
      return; // la confirmation passe par le bouton ✓ du HUD
    }
    final sel = c.selection;
    // Avec une sélection, un appui près d'un bâtiment sur le sol doit rester
    // un ordre de déplacement : pas de tolérance sur les cases voisines.
    final hit = c.pick(pos, touch: true, buildingNeighbors: sel.isEmpty);
    final ownUnit =
        hit.kind == PickKind.unit &&
        c.world.units[hit.id]?.owner == c.localPlayer;
    final ownBuilding =
        hit.kind == PickKind.building &&
        c.world.buildings[hit.id]?.owner == c.localPlayer;
    if (ownUnit || ownBuilding) {
      if (sel.contains(hit.id) && sel.units.length <= 1) {
        sel.clear(); // retoucher la sélection l'annule
        c.refresh();
      } else if (c.multiSelectMode && ownUnit) {
        sel.toggleUnit(hit.id);
        c.refresh();
      } else {
        c.selectAt(pos, touch: true);
      }
      return;
    }
    if (!sel.isEmpty) {
      c.orderAt(pos, touch: true);
    } else {
      c.selectAt(pos, touch: true);
    }
  }

  // ───────────────────────── Clavier ─────────────────────────

  static final Map<LogicalKeyboardKey, Offset> _panKeys =
      <LogicalKeyboardKey, Offset>{
        LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
        LogicalKeyboardKey.arrowRight: const Offset(1, 0),
        LogicalKeyboardKey.arrowUp: const Offset(0, -1),
        LogicalKeyboardKey.arrowDown: const Offset(0, 1),
        LogicalKeyboardKey.keyA: const Offset(-1, 0),
        LogicalKeyboardKey.keyD: const Offset(1, 0),
        LogicalKeyboardKey.keyW: const Offset(0, -1),
        LogicalKeyboardKey.keyS: const Offset(0, 1),
      };

  static const List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  /// Renvoie vrai si la touche a été traitée.
  bool keyEvent(KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyUpEvent) {
      _held.remove(k);
      return _panKeys.containsKey(k);
    }
    if (e is KeyDownEvent) _held.add(k);
    if (e is! KeyDownEvent) return _panKeys.containsKey(k);

    if (k == LogicalKeyboardKey.escape) {
      if (c.placing != null) {
        c.cancelPlacement();
      } else if (!c.selection.isEmpty) {
        c.selection.clear();
        c.refresh();
      } else {
        onMenu?.call();
      }
      return true;
    }
    if (k == LogicalKeyboardKey.space) {
      c.togglePause();
      return true;
    }
    if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.numpadAdd ||
        k == LogicalKeyboardKey.add) {
      c.loop.speedUp();
      c.refresh();
      return true;
    }
    if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      c.loop.speedDown();
      c.refresh();
      return true;
    }
    if (k == LogicalKeyboardKey.period ||
        k == LogicalKeyboardKey.numpadDecimal) {
      c.selectNextIdleVillager();
      return true;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      c.requestDelete();
      return true;
    }
    if (k == LogicalKeyboardKey.home) {
      final p = c.world.players[c.localPlayer];
      c.camera.centerOnTile(p.startX + 0.5, p.startY + 0.5);
      return true;
    }
    final digit = _digits.indexOf(k);
    if (digit >= 0) {
      c.controlGroup(digit, assign: _ctrl);
      return true;
    }
    if (k == LogicalKeyboardKey.keyH && _ctrl) {
      c.debug.stats = !c.debug.stats;
      return true;
    }
    if (k == LogicalKeyboardKey.f3) {
      c.setDebug(enabled: !c.debug.any);
      return true;
    }
    return _panKeys.containsKey(k);
  }

  /// Défilement clavier + bords d'écran (pixels écran / seconde).
  Offset panVelocity({required bool edgeScroll}) {
    var v = Offset.zero;
    for (final k in _held) {
      final d = _panKeys[k];
      if (d != null) v += d;
    }
    if (v != Offset.zero) {
      final len = v.distance;
      return v / len * 900;
    }
    if (edgeScroll && pointerInside && _touches.isEmpty && !_dragging) {
      return c.camera.edgeScrollVelocity(hover);
    }
    return Offset.zero;
  }

  /// Relâche toutes les touches (perte de focus : pas de touche « collée »).
  void releaseAll() {
    _held.clear();
    selectionRect = null;
    _dragging = false;
    _middlePan = false;
    _downPos = null;
    _touches.clear();
    _wasPinching = false;
  }

  /// Pause automatique quand la fenêtre perd le focus (option).
  void focusLost() {
    releaseAll();
    c.pause(PauseReason.lifecycle);
  }

  void focusGained() => c.resume(PauseReason.lifecycle);
}
