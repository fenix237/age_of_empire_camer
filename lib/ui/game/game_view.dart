import 'dart:async';
import 'dart:io';

import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/game/input.dart';
import 'package:age_of_empire_camer/game/royaumes_game.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

/// Vue de jeu : hôte Flame + entrées souris / clavier / tactile.
///
/// Gère la pause automatique en arrière-plan et à la perte de focus : la
/// partie ne reprend jamais seule, l'écran de pause propose « Reprendre ».
class GameView extends StatefulWidget {
  const GameView({required this.controller, required this.onMenu, super.key});

  final GameController controller;
  final VoidCallback onMenu;

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> with WidgetsBindingObserver {
  late final GameInput _input;
  late final RoyaumesGame _game;
  final FocusNode _focus = FocusNode(debugLabel: 'game');

  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _input = GameInput(c, onMenu: widget.onMenu);
    _game = RoyaumesGame(
      controller: c,
      input: _input,
      panVelocity: () => _input.panVelocity(edgeScroll: Platform.isWindows),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Pas de reprise automatique : l'écran de pause propose « Reprendre ».
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _input.releaseAll();
        c.pause(PauseReason.lifecycle);
        if (state == AppLifecycleState.paused) unawaited(c.autosave());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onFocusChange: (has) {
        if (!has) _input.releaseAll();
      },
      onKeyEvent: (node, event) => _input.keyEvent(event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _focus.requestFocus();
          _input.pointerDown(e);
        },
        onPointerMove: _input.pointerMove,
        onPointerUp: _input.pointerUp,
        onPointerCancel: _input.pointerCancel,
        onPointerSignal: _input.pointerSignal,
        onPointerPanZoomUpdate: _input.panZoomUpdate,
        child: MouseRegion(
          onHover: _input.pointerHover,
          onExit: (_) => _input.pointerExit(),
          cursor: c.placing != null
              ? SystemMouseCursors.precise
              : SystemMouseCursors.basic,
          child: GameWidget<RoyaumesGame>(game: _game),
        ),
      ),
    );
  }
}
