import 'dart:async';

import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/ui/game/game_view.dart';
import 'package:age_of_empire_camer/ui/hud/hud.dart';
import 'package:age_of_empire_camer/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Écran de partie : vue de jeu + HUD + menu pause.
///
/// Implémente [CloseGuard] : fermeture de la fenêtre / Alt+F4 /
/// « Quitter » ⇒ dialogue « Sauvegarder et quitter » (Analyse §15.3).
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({required this.controller, super.key});

  final GameController controller;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> implements CloseGuard {
  int _savedTick = -1;
  late final CloseCoordinator _coordinator;

  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _savedTick = c.world.tick;
    _coordinator = ref.read(closeCoordinatorProvider)..setGuard(this);
  }

  @override
  void dispose() {
    _coordinator.setGuard(null);
    c.dispose();
    super.dispose();
  }

  // ── CloseGuard ──

  @override
  bool get hasUnsavedChanges => c.world.tick != _savedTick;

  @override
  Future<CloseDecision> askUser() async {
    c.pause(PauseReason.dialog);
    final r = await showDialog<CloseDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Quitter la partie ?'),
        content: const Text('La partie en cours n’est pas sauvegardée.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, CloseDecision.cancel),
            child: const Text(S.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, CloseDecision.quitWithoutSaving),
            child: const Text('Quitter sans sauvegarder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, CloseDecision.saveAndQuit),
            child: const Text('Sauvegarder et quitter'),
          ),
        ],
      ),
    );
    final decision = r ?? CloseDecision.cancel;
    if (decision == CloseDecision.cancel) c.resume(PauseReason.dialog);
    return decision;
  }

  @override
  Future<bool> save() async {
    final ok = await c.saveTo('quicksave');
    if (ok) _savedTick = c.world.tick;
    return ok;
  }

  // ── Menu pause / navigation ──

  Future<void> _quitToMenu() async {
    if (hasUnsavedChanges) {
      final choice = await showDialog<CloseDecision>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Quitter vers le menu ?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, CloseDecision.cancel),
              child: const Text(S.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, CloseDecision.quitWithoutSaving),
              child: const Text('Sans sauvegarder'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, CloseDecision.saveAndQuit),
              child: const Text('Sauvegarder'),
            ),
          ],
        ),
      );
      if (choice == null || choice == CloseDecision.cancel) return;
      if (choice == CloseDecision.saveAndQuit && !await save()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sauvegarde impossible (disque plein ?)'),
          ),
        );
        return;
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _openMenu() {
    c.pause(PauseReason.menu);
  }

  /// Android : Retour ⇒ menu pause (jamais de sortie directe).
  void _onBack() {
    if (c.placing != null) {
      c.cancelPlacement();
    } else if (c.loop.pauseReasons.contains(PauseReason.menu)) {
      c.resume(PauseReason.menu);
    } else {
      _openMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GameView(controller: c, onMenu: _openMenu),
            Hud(controller: c, onMenu: _openMenu),
            DeleteConfirmation(controller: c),
            ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final reasons = c.loop.pauseReasons;
                final show =
                    reasons.contains(PauseReason.menu) ||
                    reasons.contains(PauseReason.lifecycle);
                if (!show) return const SizedBox.shrink();
                return _PauseMenu(
                  lifecycle: reasons.contains(PauseReason.lifecycle),
                  onResume: () {
                    c
                      ..resume(PauseReason.menu)
                      ..resume(PauseReason.lifecycle);
                  },
                  onSave: () async {
                    final ok = await save();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok ? 'Partie sauvegardée' : 'Sauvegarde impossible',
                        ),
                      ),
                    );
                  },
                  onQuit: () => unawaited(_quitToMenu()),
                  debugOn: c.debug.any,
                  onDebug: (on) {
                    c.setDebug(enabled: on);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PauseMenu extends StatelessWidget {
  const _PauseMenu({
    required this.lifecycle,
    required this.onResume,
    required this.onSave,
    required this.onQuit,
    required this.debugOn,
    required this.onDebug,
  });

  final bool lifecycle;
  final VoidCallback onResume;
  final VoidCallback onSave;
  final VoidCallback onQuit;
  final bool debugOn;
  final ValueChanged<bool> onDebug;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    lifecycle ? 'Partie en pause' : 'Menu',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: onResume,
                    child: const Text(S.resume),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: onSave,
                    child: const Text(S.save),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mode debug (FPS, grille, chemins)'),
                    value: debugOn,
                    onChanged: onDebug,
                  ),
                  FilledButton.tonal(
                    onPressed: onQuit,
                    child: const Text(S.quitToMenu),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Raccourci commun pour quitter l'appli depuis un menu (Android : Retour).
Future<void> exitApp() => SystemNavigator.pop();
