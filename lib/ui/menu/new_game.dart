import 'dart:math' as math;

import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/ui/game/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Paramètres d'une nouvelle partie (menu d'escarmouche minimal).
class NewGameOptions {
  const NewGameOptions({this.size = 64, this.seed = 1, this.players = 2});

  final int size;
  final int seed;
  final int players;
}

Future<void> showNewGameDialog(BuildContext context, WidgetRef ref) async {
  final opts = await showDialog<NewGameOptions>(
    context: context,
    builder: (context) => const _NewGameDialog(),
  );
  if (opts == null || !context.mounted) return;
  await startGame(context, ref, opts);
}

Future<void> startGame(
  BuildContext context,
  WidgetRef ref,
  NewGameOptions opts,
) async {
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
  );
  final controller = GameController(
    world: world,
    defs: defs,
    saveStore: ref.read(saveStoreProvider),
  );
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
  final controller = GameController(world: world, defs: defs, saveStore: store);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => GameScreen(controller: controller)),
  );
}

void _error(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _NewGameDialog extends StatefulWidget {
  const _NewGameDialog();

  @override
  State<_NewGameDialog> createState() => _NewGameDialogState();
}

class _NewGameDialogState extends State<_NewGameDialog> {
  int size = 64;
  final TextEditingController seed = TextEditingController(
    text: '${math.Random().nextInt(100000)}',
  );

  @override
  void dispose() {
    seed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle partie'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Taille de la carte'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 64, label: Text('Petite')),
              ButtonSegment<int>(value: 96, label: Text('Moyenne')),
              ButtonSegment<int>(value: 128, label: Text('Grande')),
            ],
            selected: <int>{size},
            onSelectionChanged: (s) => setState(() => size = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: seed,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Graine de la carte'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Un adversaire inactif est placé sur la carte '
            '(le combat et l’IA arrivent dans les phases suivantes).',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            NewGameOptions(size: size, seed: int.tryParse(seed.text) ?? 1),
          ),
          child: const Text('Jouer'),
        ),
      ],
    );
  }
}
