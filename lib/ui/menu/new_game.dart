import 'dart:math' as math;

import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_setup.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/systems/victory.dart';
import 'package:age_of_empire_camer/ui/game/game_screen.dart';
import 'package:age_of_empire_camer/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Paramètres d'une partie d'escarmouche.
class NewGameOptions {
  const NewGameOptions({
    this.size = 64,
    this.seed = 1,
    this.style = 0,
    this.clan = 0,
    this.aiCount = 1,
    this.difficulty = 1,
    this.victory = VictoryMode.conquest,
    this.resourcePercent = 100,
    this.speed = 1,
    this.spectator = false,
  });

  final int size;
  final int seed;

  /// Style de carte (`balance.mapStyles`).
  final int style;

  /// Clan du joueur (indice dans `Defs.clans`).
  final int clan;

  /// Nombre d'adversaires IA (en spectateur : nombre d'IA qui s'affrontent).
  final int aiCount;

  /// Difficulté de l'IA (0 facile, 1 normal, 2 difficile).
  final int difficulty;
  final int victory;

  /// Ressources de départ en pourcentage de la valeur standard.
  final int resourcePercent;
  final double speed;

  /// Aucun joueur humain : on regarde des IA s'affronter.
  final bool spectator;

  int get players => spectator ? math.max(2, aiCount) : aiCount + 1;
}

/// Réglages des joueurs : l'humain (sauf spectateur) en premier, puis des IA
/// dont les clans varient de façon déterministe avec la graine.
List<PlayerSetup> skirmishSetups(Defs defs, NewGameOptions o) {
  final playable = <int>[
    for (final c in defs.clans)
      if (c.playable) c.index,
  ];
  final used = <int>{if (!o.spectator) o.clan};
  var pick = o.seed.abs();
  int nextClan() {
    for (var k = 0; k < playable.length; k++) {
      final c = playable[(pick + k) % playable.length];
      if (!used.contains(c)) {
        pick += k + 1;
        return c;
      }
    }
    final c = playable[pick % playable.length];
    pick++;
    return c;
  }

  final level = o.difficulty.clamp(0, defs.ai.difficulties.length - 1);
  final ais = o.spectator ? o.players : o.aiCount;
  final out = <PlayerSetup>[if (!o.spectator) PlayerSetup(clan: o.clan)];
  for (var i = 0; i < ais; i++) {
    final c = nextClan();
    used.add(c);
    out.add(PlayerSetup(clan: c, aiLevel: level));
  }
  return out;
}

/// Date locale au format `aaaa-mm-jj` (clé du défi du jour).
String dailyKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Défi du jour : partie d'escarmouche entièrement fixée par la date locale
/// (graine, carte, clan, adversaire), donc identique pour tout le monde.
NewGameOptions dailyOptions(DateTime d, Defs defs) {
  final seed = d.year * 10000 + d.month * 100 + d.day;
  final playable = <int>[
    for (final c in defs.clans)
      if (c.playable) c.index,
  ];
  return NewGameOptions(
    seed: seed,
    style: seed % defs.balance.mapStyles.length,
    clan: playable[seed % playable.length],
    difficulty: 1 + seed % 2,
    resourcePercent: 100 + 50 * (seed % 2),
  );
}

Future<void> showNewGameDialog(BuildContext context, WidgetRef ref) async {
  final defs = await ref.read(defsProvider.future);
  if (!context.mounted) return;
  final opts = await showDialog<NewGameOptions>(
    context: context,
    builder: (context) => SkirmishDialog(defs: defs),
  );
  if (opts == null || !context.mounted) return;
  await startGame(context, ref, opts);
}

Future<void> startGame(
  BuildContext context,
  WidgetRef ref,
  NewGameOptions opts, {
  String? daily,
}) async {
  final Defs defs;
  try {
    defs = await ref.read(defsProvider.future);
  } on DataException catch (e) {
    if (context.mounted) _error(context, 'Données du jeu invalides : $e');
    return;
  }
  final world = createGame(
    defs,
    seed: opts.seed,
    size: opts.size,
    players: opts.players,
    style: opts.style,
    setups: skirmishSetups(defs, opts),
    startingResources: defs.balance.startingResources.scaled(
      opts.resourcePercent,
      100,
    ),
    victoryMode: opts.victory,
  );
  final controller = GameController(
    world: world,
    defs: defs,
    saveStore: ref.read(saveStoreProvider),
  );
  controller
    ..loop.speed = opts.speed
    ..dailyKey = daily;
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => GameScreen(controller: controller)),
  );
}

/// Reprend la sauvegarde la plus récente (manuelle ou automatique).
Future<void> resumeGame(BuildContext context, WidgetRef ref) async {
  final store = ref.read(saveStoreProvider);
  final slot = store?.newestSlot();
  if (store == null || slot == null) return;
  final defs = await ref.read(defsProvider.future);
  final world = await store.loadWorld(defs, slot);
  if (!context.mounted) return;
  if (world == null) {
    _error(
      context,
      'Sauvegarde illisible : impossible de reprendre la partie.',
    );
    return;
  }
  if (world.missionRaw != null) {
    final campaign = await ref.read(campaignProvider.future);
    attachMission(world, campaign);
  }
  if (!context.mounted) return;
  final controller = GameController(world: world, defs: defs, saveStore: store);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => GameScreen(controller: controller)),
  );
}

void _error(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Menu d'escarmouche : carte, clan, adversaires, victoire, ressources,
/// vitesse et mode spectateur.
class SkirmishDialog extends StatefulWidget {
  const SkirmishDialog({required this.defs, super.key});

  final Defs defs;

  @override
  State<SkirmishDialog> createState() => _SkirmishDialogState();
}

class _SkirmishDialogState extends State<SkirmishDialog> {
  int size = 64;
  int style = 0;
  int clan = 0;
  int aiCount = 1;
  int difficulty = 1;
  int victory = VictoryMode.conquest;
  int resources = 100;
  double speed = 1;
  bool spectator = false;
  final TextEditingController seed = TextEditingController(
    text: '${math.Random().nextInt(100000)}',
  );

  @override
  void dispose() {
    seed.dispose();
    super.dispose();
  }

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final defs = widget.defs;
    final playable = defs.clans.where((c) => c.playable).toList();
    final diff = defs.ai.difficulties[difficulty];
    final bonus = diff.shownBonus ? diff.gatherBonusPercent : 0;
    final counts = spectator ? const <int>[2, 3, 4] : const <int>[1, 2, 3];
    return AlertDialog(
      title: const Text('Escarmouche'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _section(
                'Taille de la carte',
                SegmentedButton<int>(
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(value: 64, label: Text('Petite')),
                    ButtonSegment<int>(value: 96, label: Text('Moyenne')),
                    ButtonSegment<int>(value: 128, label: Text('Grande')),
                  ],
                  selected: <int>{size},
                  onSelectionChanged: (s) => setState(() => size = s.first),
                ),
              ),
              _section(
                'Type de carte',
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    for (var i = 0; i < S.mapStyles.length; i++)
                      ChoiceChip(
                        label: Text(S.mapStyles[i]),
                        selected: style == i,
                        onSelected: (_) => setState(() => style = i),
                      ),
                  ],
                ),
              ),
              _section(
                'Graine de la carte',
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: seed,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Graine aléatoire',
                      onPressed: () => setState(
                        () => seed.text = '${math.Random().nextInt(100000)}',
                      ),
                      icon: const Icon(Icons.casino),
                    ),
                  ],
                ),
              ),
              if (!spectator)
                _section(
                  'Votre clan',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 6,
                        children: <Widget>[
                          for (final c in playable)
                            ChoiceChip(
                              label: Text(S.clan(c.id)),
                              selected: clan == c.index,
                              onSelected: (_) => setState(() => clan = c.index),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        S.clanDescription(defs.clans[clan].id),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              _section(
                spectator ? 'Nombre d’IA' : 'Nombre d’adversaires IA',
                SegmentedButton<int>(
                  segments: <ButtonSegment<int>>[
                    for (final n in counts)
                      ButtonSegment<int>(value: n, label: Text('$n')),
                  ],
                  selected: <int>{aiCount.clamp(counts.first, counts.last)},
                  onSelectionChanged: (s) => setState(() => aiCount = s.first),
                ),
              ),
              _section(
                'Difficulté de l’IA',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SegmentedButton<int>(
                      segments: <ButtonSegment<int>>[
                        for (var i = 0; i < S.difficulties.length; i++)
                          ButtonSegment<int>(
                            value: i,
                            label: Text(S.difficulties[i]),
                          ),
                      ],
                      selected: <int>{difficulty},
                      onSelectionChanged: (s) =>
                          setState(() => difficulty = s.first),
                    ),
                    if (bonus > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Bonus de l’IA : +$bonus % de récolte.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFFB070),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _section(
                'Condition de victoire',
                SegmentedButton<int>(
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(
                      value: VictoryMode.conquest,
                      label: Text('Conquête'),
                    ),
                    ButtonSegment<int>(
                      value: VictoryMode.townCenters,
                      label: Text('Centres-villes'),
                    ),
                  ],
                  selected: <int>{victory},
                  onSelectionChanged: (s) => setState(() => victory = s.first),
                ),
              ),
              _section(
                'Ressources de départ',
                SegmentedButton<int>(
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(value: 50, label: Text('Faibles')),
                    ButtonSegment<int>(value: 100, label: Text('Normales')),
                    ButtonSegment<int>(value: 200, label: Text('Élevées')),
                  ],
                  selected: <int>{resources},
                  onSelectionChanged: (s) =>
                      setState(() => resources = s.first),
                ),
              ),
              _section(
                'Vitesse de jeu',
                SegmentedButton<double>(
                  segments: <ButtonSegment<double>>[
                    for (final v in GameLoop.speeds)
                      ButtonSegment<double>(
                        value: v,
                        label: Text(
                          '×${v == v.roundToDouble() ? v.round() : v}',
                        ),
                      ),
                  ],
                  selected: <double>{speed},
                  onSelectionChanged: (s) => setState(() => speed = s.first),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mode spectateur'),
                subtitle: const Text('Regardez des IA s’affronter.'),
                value: spectator,
                onChanged: (v) => setState(() {
                  spectator = v;
                  aiCount = v ? math.max(2, aiCount) : math.min(3, aiCount);
                }),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            NewGameOptions(
              size: size,
              seed: int.tryParse(seed.text) ?? 1,
              style: style,
              clan: clan,
              aiCount: spectator ? math.max(2, aiCount) : aiCount,
              difficulty: difficulty,
              victory: victory,
              resourcePercent: resources,
              speed: speed,
              spectator: spectator,
            ),
          ),
          child: const Text('Jouer'),
        ),
      ],
    );
  }
}
