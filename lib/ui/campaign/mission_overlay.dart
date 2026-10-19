import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_runtime.dart';
import 'package:age_of_empire_camer/ui/campaign/campaign_screen.dart';
import 'package:age_of_empire_camer/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Surcouche d'une mission de campagne : objectifs, aide du tutoriel,
/// dialogues (la partie est en pause pendant qu'on les lit).
class MissionOverlay extends StatelessWidget {
  const MissionOverlay({required this.controller, super.key});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final m = controller.world.mission;
    if (m == null) return const SizedBox.shrink();
    return Stack(
      children: <Widget>[
        Positioned(
          right: 8,
          top: 56,
          child: ObjectivesPanel(controller: controller),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 190,
          child: Center(child: HintBanner(controller: controller)),
        ),
        DialogOverlay(controller: controller),
      ],
    );
  }
}

class ObjectivesPanel extends StatelessWidget {
  const ObjectivesPanel({required this.controller, super.key});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final m = controller.world.mission;
        if (m == null) return const SizedBox.shrink();
        final list = m.visibleObjectives;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xCC1B1410),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x44FFFFFF)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  m.def.title,
                  style: const TextStyle(
                    color: Color(0xFFFFD35A),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                for (final o in list)
                  _ObjectiveRow(
                    label: o.label,
                    optional: o.optional,
                    state: m.objectiveState(o.id),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ObjectiveRow extends StatelessWidget {
  const _ObjectiveRow({
    required this.label,
    required this.optional,
    required this.state,
  });

  final String label;
  final bool optional;
  final int state;

  @override
  Widget build(BuildContext context) {
    final done = state == ObjState.done;
    final failed = state == ObjState.failed;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            done
                ? Icons.check_circle
                : (failed ? Icons.cancel : Icons.radio_button_unchecked),
            size: 14,
            color: done
                ? const Color(0xFF6FD36F)
                : (failed ? const Color(0xFFE05555) : Colors.white70),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              optional ? '$label (facultatif)' : label,
              style: TextStyle(
                fontSize: 12,
                color: done ? Colors.white54 : Colors.white,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HintBanner extends StatelessWidget {
  const HintBanner({required this.controller, super.key});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hint = controller.world.mission?.hint ?? '';
        if (hint.isEmpty || controller.world.gameOver) {
          return const SizedBox.shrink();
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            color: const Color(0xDD3A2A1E),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: Color(0xFFFFD35A),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      hint,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dialogue modal : une réplique à la fois ; la partie reste en pause.
class DialogOverlay extends StatefulWidget {
  const DialogOverlay({required this.controller, super.key});

  final GameController controller;

  @override
  State<DialogOverlay> createState() => _DialogOverlayState();
}

class _DialogOverlayState extends State<DialogOverlay> {
  int _line = 0;
  bool _paused = false;

  GameController get c => widget.controller;

  void _next() {
    final m = c.world.mission!;
    final dialog = m.dialogs.first;
    if (_line + 1 < dialog.length) {
      setState(() => _line++);
      return;
    }
    m.dialogs.removeAt(0);
    _line = 0;
    if (m.dialogs.isEmpty && _paused) {
      _paused = false;
      c.resume(PauseReason.dialog);
    }
    c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final m = c.world.mission;
        if (m == null || m.dialogs.isEmpty) return const SizedBox.shrink();
        if (!_paused) {
          _paused = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            c.pause(PauseReason.dialog);
          });
        }
        final dialog = m.dialogs.first;
        final line = dialog[_line.clamp(0, dialog.length - 1)];
        return Positioned.fill(
          child: GestureDetector(
            onTap: _next,
            child: ColoredBox(
              color: Colors.black38,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Card(
                      color: const Color(0xEE2A1F17),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF8B5A2B),
                                  child: Text(
                                    line.speaker.isEmpty
                                        ? '?'
                                        : line.speaker.characters.first,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  line.speaker,
                                  style: const TextStyle(
                                    color: Color(0xFFFFD35A),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              line.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _next,
                                child: Text(
                                  _line + 1 < dialog.length
                                      ? 'Suite'
                                      : 'Fermer',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Écran de fin de mission : résultat, étoiles, fin obtenue, déblocages.
class MissionEndScreen extends ConsumerStatefulWidget {
  const MissionEndScreen({required this.controller, super.key});

  final GameController controller;

  @override
  ConsumerState<MissionEndScreen> createState() => _MissionEndScreenState();
}

class _MissionEndScreenState extends ConsumerState<MissionEndScreen> {
  bool _recorded = false;
  bool _paused = false;
  List<String> _newItems = const <String>[];

  GameController get c => widget.controller;

  void _record(MissionRuntime m) {
    _recorded = true;
    if (!m.won) return;
    final campaign = ref.read(campaignProvider).valueOrNull;
    final progress = ref.read(progressProvider);
    final before = campaign == null
        ? const <String>{}
        : progress.unlocked(campaign);
    _newItems = <String>[
      for (final id in m.def.rewards)
        if (!before.contains(id)) id,
    ];
    ref
        .read(progressProvider.notifier)
        .update(
          progress.withWin(
            m.def,
            stars: m.stars,
            seconds: m.endTick ~/ 10,
            difficulty: m.difficulty,
            ending: m.ending,
          ),
        );
  }

  String _name(String id) {
    final n = S.unit(id);
    return n == id ? S.building(id) : n;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final m = c.world.mission;
        if (m == null || m.running) return const SizedBox.shrink();
        if (!_paused) {
          _paused = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            c.pause(PauseReason.dialog);
          });
        }
        if (!_recorded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_recorded) setState(() => _record(m));
          });
        }
        final campaign = ref.watch(campaignProvider).valueOrNull;
        final hasNext =
            campaign != null &&
            campaign.missions.indexOf(m.def) + 1 < campaign.missions.length;
        final seconds = m.endTick ~/ 10;
        final reason = m.loseReason == 'lose'
            ? 'Votre centre-ville est tombé.'
            : (m.def.objective(m.loseReason)?.label ?? '');
        return ColoredBox(
          color: Colors.black54,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        m.won ? S.victory : S.defeat,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: m.won
                                  ? const Color(0xFF6FD36F)
                                  : const Color(0xFFE05555),
                            ),
                      ),
                      Text(
                        m.def.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 10),
                      if (m.won)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            for (var i = 0; i < 3; i++)
                              Icon(
                                i < m.stars ? Icons.star : Icons.star_border,
                                color: const Color(0xFFFFD35A),
                                size: 36,
                              ),
                          ],
                        )
                      else if (reason.isNotEmpty)
                        Text(
                          'Échec : $reason',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Durée : ${seconds ~/ 60} min '
                        '${(seconds % 60).toString().padLeft(2, '0')} s · '
                        '${S.difficulties[m.difficulty]}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (m.won && m.endingText.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(m.endingText, textAlign: TextAlign.center),
                      ],
                      if (m.won && _newItems.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          'Débloqué : ${_newItems.map(_name).join(', ')}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFFD35A)),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: <Widget>[
                          if (m.won && hasNext)
                            FilledButton(
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(MissionExit.next),
                              child: const Text('Mission suivante'),
                            ),
                          FilledButton.tonal(
                            onPressed: () =>
                                Navigator.of(context).pop(MissionExit.retry),
                            child: Text(m.won ? 'Rejouer' : 'Réessayer'),
                          ),
                          FilledButton.tonal(
                            onPressed: () =>
                                Navigator.of(context).pop(MissionExit.map),
                            child: const Text('Carte du royaume'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
