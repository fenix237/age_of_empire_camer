import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/world/player.dart';
import 'package:age_of_empire_camer/ui/hud/hud.dart';
import 'package:age_of_empire_camer/ui/strings.dart';
import 'package:flutter/material.dart';

/// Touches associées aux pouvoirs d'unité et aux sorts (voir `GameInput`).
const List<String> _powerKeys = <String>['Z', 'X', 'C', 'V'];
const List<String> _spellKeys = <String>['F5', 'F6', 'F7', 'F8'];

/// Panneau de combat : pouvoirs des unités sélectionnées, jauge du tambour et
/// sorts de bataille, passage à l'âge suivant. Il n'émet que des commandes via
/// le contrôleur.
class CombatPanel extends StatelessWidget {
  const CombatPanel({
    required this.controller,
    required this.metrics,
    super.key,
  });

  final GameController controller;
  final HudMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.spectator) return const SizedBox.shrink();
        final me = controller.me;
        final defs = controller.defs;
        final powers = controller.selectedPowers;
        final spells = defs.powers.where((p) => p.isSpell).toList();
        final next = me.age + 1;
        final hasNext = next < defs.ages.length;
        final children = <Widget>[];

        if (powers.isNotEmpty) {
          children.add(
            _Row(
              label: S.powers,
              children: <Widget>[
                for (var i = 0; i < powers.length && i < 4; i++)
                  _PowerButton(
                    name: S.power(powers[i].id),
                    description: S.powerDescription(powers[i].id),
                    hotkey: _powerKeys[i],
                    cooldown: controller.powerCooldownSeconds(powers[i]),
                    cooldownTotal: powers[i].cooldownTicks / 10,
                    enabled:
                        powers[i].age <= me.age &&
                        controller.readyCasters(powers[i]).isNotEmpty,
                    locked: powers[i].age > me.age,
                    active: controller.targeting?.power == powers[i],
                    metrics: metrics,
                    onTap: () => controller.beginPower(powers[i]),
                  ),
              ],
            ),
          );
        }

        if (spells.isNotEmpty) {
          final drumMax = defs.balance.combat.drumMax;
          children.add(
            _Row(
              label: S.drum,
              header: _DrumGauge(value: me.drum, max: drumMax),
              children: <Widget>[
                for (var i = 0; i < spells.length && i < 4; i++)
                  _PowerButton(
                    name: S.power(spells[i].id),
                    description:
                        '${S.powerDescription(spells[i].id)} '
                        '(${spells[i].drumCost} d’énergie)',
                    hotkey: _spellKeys[i],
                    cooldown: me.spellCd[spells[i].index] / 10,
                    cooldownTotal: spells[i].cooldownTicks / 10,
                    enabled:
                        me.drum >= spells[i].drumCost &&
                        me.spellCd[spells[i].index] == 0,
                    cost: spells[i].drumCost,
                    active: controller.targeting?.power == spells[i],
                    metrics: metrics,
                    onTap: () => controller.beginSpell(spells[i]),
                  ),
              ],
            ),
          );
        }

        if (hasNext) {
          final age = defs.ages[next];
          final missing = controller.missingForNextAge();
          final can = missing.isEmpty && me.stock.covers(age.cost);
          children.add(
            _AgeButton(
              label: '${S.ageUp} : ${S.age(next)}',
              cost: age.cost,
              missing: missing,
              enabled: can,
              metrics: metrics,
              onTap: controller.ageUp,
            ),
          );
        }

        if (children.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final w in children)
              Padding(padding: const EdgeInsets.only(top: 6), child: w),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.children, this.header});

  final String label;
  final Widget? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xCC1B1410),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x44FFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              if (header != null) ...<Widget>[
                const SizedBox(width: 8),
                header!,
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: children),
        ],
      ),
    );
  }
}

class _DrumGauge extends StatelessWidget {
  const _DrumGauge({required this.value, required this.max});

  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final f = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Tooltip(
      message: '${S.drum} : $value / $max',
      child: SizedBox(
        width: 120,
        height: 10,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(color: Color(0xFF2A1F17)),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: f,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[Color(0xFFB8741A), Color(0xFFFFD35A)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.name,
    required this.description,
    required this.hotkey,
    required this.cooldown,
    required this.cooldownTotal,
    required this.enabled,
    required this.metrics,
    required this.onTap,
    this.cost,
    this.locked = false,
    this.active = false,
  });

  final String name;
  final String description;
  final String hotkey;
  final double cooldown;
  final double cooldownTotal;
  final bool enabled;
  final bool locked;
  final bool active;
  final int? cost;
  final HudMetrics metrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cooling = cooldown > 0 && cooldownTotal > 0;
    final k = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final size = (metrics.button + 14) * k;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: '$name — $description',
        child: Opacity(
          opacity: enabled || cooling ? 1 : 0.45,
          child: Material(
            color: active ? const Color(0xFF8B5A2B) : const Color(0xFF3A2A1E),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: SizedBox(
                width: size + 22,
                height: size,
                child: Stack(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            locked ? Icons.lock : Icons.bolt,
                            size: 16,
                            color: const Color(0xFFFFD35A),
                          ),
                          Text(
                            name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: metrics.font - 3,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (cooling)
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.bottomCenter,
                          heightFactor: (cooldown / cooldownTotal).clamp(0, 1),
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    if (cooling)
                      Center(
                        child: Text(
                          cooldown.ceil().toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 3,
                      top: 1,
                      child: Text(
                        hotkey,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    if (cost != null)
                      Positioned(
                        right: 3,
                        top: 1,
                        child: Text(
                          '$cost',
                          style: const TextStyle(
                            color: Color(0xFFFFD35A),
                            fontSize: 9,
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
    );
  }
}

class _AgeButton extends StatelessWidget {
  const _AgeButton({
    required this.label,
    required this.cost,
    required this.missing,
    required this.enabled,
    required this.metrics,
    required this.onTap,
  });

  final String label;
  final Stock cost;
  final List<String> missing;
  final bool enabled;
  final HudMetrics metrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final costText = <String>[
      for (final r in Res.values)
        if (cost[r] > 0) '${cost[r]} ${S.res(r).toLowerCase()}',
    ].join(', ');
    final need = missing.isEmpty
        ? ''
        : '\nBâtiments requis : ${missing.map(S.building).join(', ')}';
    return Tooltip(
      message: '$label — $costText$need',
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: const Color(0xFF6B3F1C),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.north_east, size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: metrics.font,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        missing.isEmpty
                            ? costText
                            : 'Requis : ${missing.map(S.building).join(', ')}',
                        style: TextStyle(
                          color: missing.isEmpty
                              ? Colors.white70
                              : const Color(0xFFFFB0B0),
                          fontSize: metrics.font - 2,
                        ),
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
  }
}

/// Bandeau « choisissez une cible » pendant le ciblage d'un pouvoir.
class TargetingBanner extends StatelessWidget {
  const TargetingBanner({required this.controller, super.key});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = controller.targeting;
        if (t == null) return const SizedBox.shrink();
        return Material(
          color: const Color(0xDD1B1410),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.gps_fixed, size: 18, color: Color(0xFFFFD35A)),
                const SizedBox(width: 8),
                Text(
                  '${S.power(t.power.id)} : touchez la cible '
                  '(clic droit ou Échap pour annuler)',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: controller.cancelTargeting,
                  child: const Text(S.cancel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Écran de fin de partie : résultat, statistiques par joueur, suite.
class EndScreen extends StatefulWidget {
  const EndScreen({
    required this.controller,
    required this.onQuit,
    this.onResult,
    super.key,
  });

  final GameController controller;
  final VoidCallback onQuit;

  /// Appelé une fois à l'affichage du résultat (victoire, durée en secondes).
  final void Function({required bool won, required int seconds})? onResult;

  @override
  State<EndScreen> createState() => _EndScreenState();
}

class _EndScreenState extends State<EndScreen> {
  bool _paused = false;
  bool _reported = false;

  GameController get c => widget.controller;

  bool get _show {
    if (c.endAcknowledged) return false;
    return c.world.gameOver || (!c.spectator && c.me.defeated);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (!_show) return const SizedBox.shrink();
        if (!_paused) {
          _paused = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            c.pause(PauseReason.dialog);
          });
        }
        final w = c.world;
        final String title;
        final Color color;
        if (c.spectator) {
          title = w.winnerTeam >= 0
              ? 'L’équipe ${w.winnerTeam + 1} l’emporte'
              : S.draw;
          color = const Color(0xFFFFD35A);
        } else if (w.gameOver && w.winnerTeam == c.me.team) {
          title = S.victory;
          color = const Color(0xFF6FD36F);
        } else if (w.gameOver && w.winnerTeam == -2) {
          title = S.draw;
          color = const Color(0xFFFFD35A);
        } else {
          title = S.defeat;
          color = const Color(0xFFE05555);
        }
        final seconds = w.tick ~/ 10;
        if (!_reported) {
          _reported = true;
          final won = w.gameOver && w.winnerTeam == c.me.team && !c.spectator;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onResult?.call(won: won, seconds: seconds);
          });
        }
        final duration =
            '${seconds ~/ 60} min ${(seconds % 60).toString().padLeft(2, '0')} s';
        return ColoredBox(
          color: Colors.black54,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'Durée : $duration',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      Flexible(child: _StatsTable(controller: c)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (!w.gameOver || c.spectator)
                            FilledButton.tonal(
                              onPressed: () {
                                c.endAcknowledged = true;
                                c.resume(PauseReason.dialog);
                                c.refresh();
                              },
                              child: const Text('Continuer à regarder'),
                            ),
                          if (!w.gameOver || c.spectator)
                            const SizedBox(width: 12),
                          FilledButton(
                            onPressed: widget.onQuit,
                            child: const Text(S.quitToMenu),
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

String playerLabel(GameController c, Player p) {
  final clan = p.clan >= 0 ? S.clan(c.defs.clans[p.clan].id) : '';
  final String who;
  if (p.id == c.localPlayer && !c.spectator) {
    who = 'Vous';
  } else if (p.aiLevel >= 0) {
    final bonus = p.aiGatherBonus > 0 ? ' +${p.aiGatherBonus} %' : '';
    who = 'IA ${p.id + 1} (${S.difficulties[p.aiLevel]}$bonus)';
  } else {
    who = 'Joueur ${p.id + 1}';
  }
  return clan.isEmpty ? who : '$who\n$clan';
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final players = controller.world.players;
    final rows = <(String, int Function(PlayerStats))>[
      ('Unités ennemies tuées', (s) => s.unitsKilled),
      ('Unités perdues', (s) => s.unitsLost),
      ('Bâtiments détruits', (s) => s.buildingsDestroyed),
      ('Bâtiments perdus', (s) => s.buildingsLost),
      ('Dégâts infligés', (s) => s.damageDealt),
      ('Unités formées', (s) => s.unitsTrained),
      ('Bâtiments construits', (s) => s.buildingsBuilt),
      ('Recherches', (s) => s.researches),
      ('Plus grande armée', (s) => s.peakArmy),
      ('Ressources récoltées', (s) => s.totalGathered),
      ('Pouvoirs utilisés', (s) => s.powersUsed),
      ('Sorts lancés', (s) => s.spellsCast),
    ];
    const head = TextStyle(color: Colors.white70, fontSize: 12);
    return SingleChildScrollView(
      child: Table(
        columnWidths: const <int, TableColumnWidth>{0: FlexColumnWidth(2)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: <TableRow>[
          TableRow(
            children: <Widget>[
              const SizedBox.shrink(),
              for (final p in players)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    playerLabel(controller, p),
                    textAlign: TextAlign.center,
                    style: head.copyWith(
                      color: p.defeated ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          for (final (label, get) in rows)
            TableRow(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(label, style: head),
                ),
                for (final p in players)
                  Text(
                    '${get(p.stats)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Confirmation d'abandon (menu pause).
Future<bool> confirmResign(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Abandonner la partie ?'),
      content: const Text('Vous serez déclaré vaincu.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(S.resign),
        ),
      ],
    ),
  );
  return r ?? false;
}
