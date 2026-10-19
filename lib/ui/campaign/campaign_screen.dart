import 'dart:async';

import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/meta/campaign_progress.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_def.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_setup.dart';
import 'package:age_of_empire_camer/ui/game/game_screen.dart';
import 'package:age_of_empire_camer/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ce que le joueur choisit en quittant l'écran de fin d'une mission.
enum MissionExit { next, retry, map }

/// Carte du royaume : les missions s'enchaînent le long du fleuve ; les
/// réussites donnent des étoiles et débloquent unités et bâtiments.
class CampaignScreen extends ConsumerWidget {
  const CampaignScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaign = ref.watch(campaignProvider);
    final progress = ref.watch(progressProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campagne : le royaume du Fleuve'),
        actions: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.star, color: Color(0xFFFFD35A), size: 18),
                  const SizedBox(width: 4),
                  Text('${progress.totalStars()}'),
                ],
              ),
            ),
          ),
        ],
      ),
      body: campaign.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Campagne illisible : $e'),
          ),
        ),
        data: (c) => _Kingdom(campaign: c, progress: progress),
      ),
    );
  }
}

class _Kingdom extends ConsumerWidget {
  const _Kingdom({required this.campaign, required this.progress});

  final CampaignDef campaign;
  final CampaignProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        const r = 30.0;
        Offset at(MissionDef m) => Offset(
          r + (size.width - 2 * r) * m.kingdomX / 100,
          r + (size.height - 2 * r - 40) * m.kingdomY / 100,
        );
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: _MapPainter(<Offset>[
                  for (final m in campaign.missions) at(m),
                ]),
              ),
            ),
            for (final m in campaign.missions)
              Positioned(
                left: at(m).dx - r,
                top: at(m).dy - r,
                child: _MissionNode(
                  mission: m,
                  progress: progress,
                  radius: r,
                  onTap: () =>
                      unawaited(showMissionBriefing(context, ref, campaign, m)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF2E4A2A),
            Color(0xFF4A6B33),
            Color(0xFF6B5A33),
          ],
        ).createShader(Offset.zero & size),
    );
    // Le fleuve.
    final river = Path()
      ..moveTo(0, size.height * 0.75)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.95,
        size.width * 0.45,
        size.height * 0.4,
        size.width * 0.65,
        size.height * 0.55,
      )
      ..cubicTo(
        size.width * 0.8,
        size.height * 0.65,
        size.width * 0.9,
        size.height * 0.3,
        size.width,
        size.height * 0.25,
      );
    canvas.drawPath(
      river,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xAA3FA0C7),
    );
    // Route entre les missions.
    if (points.length > 1) {
      final road = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final a = points[i - 1];
        final b = points[i];
        road.quadraticBezierTo(
          (a.dx + b.dx) / 2,
          a.dy + (b.dy - a.dy) * 0.2 - 18,
          b.dx,
          b.dy,
        );
      }
      canvas.drawPath(
        road,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xCCE8D8B0),
      );
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.points != points;
}

class _MissionNode extends StatelessWidget {
  const _MissionNode({
    required this.mission,
    required this.progress,
    required this.radius,
    required this.onTap,
  });

  final MissionDef mission;
  final CampaignProgress progress;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = progress.isDone(mission.id);
    final open = progress.isAvailable(mission);
    final rec = progress.missions[mission.id];
    final color = done
        ? const Color(0xFFE6B422)
        : (open ? const Color(0xFFB8741A) : const Color(0xFF55555A));
    return SizedBox(
      width: radius * 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Tooltip(
            message: open || done
                ? mission.title
                : 'Terminez la mission précédente',
            child: Material(
              color: color,
              shape: const CircleBorder(
                side: BorderSide(color: Colors.white70, width: 2),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: open || done ? onTap : null,
                child: SizedBox(
                  width: radius * 2,
                  height: radius * 2,
                  child: Center(
                    child: open || done
                        ? Text(
                            '${mission.index + 1}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lock, color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < 3; i++)
                Icon(
                  Icons.star,
                  size: 12,
                  color: rec != null && i < rec.stars
                      ? const Color(0xFFFFD35A)
                      : Colors.black38,
                ),
            ],
          ),
          Text(
            mission.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              shadows: <Shadow>[Shadow(blurRadius: 3)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fiche de mission : briefing, objectifs, record, récompenses, difficulté.
Future<void> showMissionBriefing(
  BuildContext context,
  WidgetRef ref,
  CampaignDef campaign,
  MissionDef m,
) async {
  final diff = await showDialog<int>(
    context: context,
    builder: (_) => _BriefingDialog(
      mission: m,
      record: ref.read(progressProvider).missions[m.id],
    ),
  );
  if (diff == null || !context.mounted) return;
  await playMission(context, ref, campaign, m, diff);
}

/// Lance une mission et enchaîne selon le choix de l'écran de fin.
Future<void> playMission(
  BuildContext context,
  WidgetRef ref,
  CampaignDef campaign,
  MissionDef m,
  int difficulty,
) async {
  var current = m;
  while (true) {
    final defs = await ref.read(defsProvider.future);
    final progress = ref.read(progressProvider);
    final world = createMissionGame(
      defs,
      current,
      difficulty: difficulty,
      unlocked: progress.unlocked(campaign),
    );
    final controller = GameController(
      world: world,
      defs: defs,
      saveStore: ref.read(saveStoreProvider),
    );
    if (!context.mounted) return;
    final exit = await Navigator.of(context).push<MissionExit>(
      MaterialPageRoute<MissionExit>(
        builder: (_) => GameScreen(controller: controller),
      ),
    );
    if (!context.mounted) return;
    if (exit == MissionExit.retry) continue;
    if (exit == MissionExit.next) {
      final i = campaign.missions.indexOf(current);
      if (i + 1 < campaign.missions.length) {
        current = campaign.missions[i + 1];
        continue;
      }
    }
    return;
  }
}

class _BriefingDialog extends StatefulWidget {
  const _BriefingDialog({required this.mission, required this.record});

  final MissionDef mission;
  final MissionRecord? record;

  @override
  State<_BriefingDialog> createState() => _BriefingDialogState();
}

class _BriefingDialogState extends State<_BriefingDialog> {
  int difficulty = 1;

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final rec = widget.record;
    final visible = m.objectives.where((o) => !o.hidden).toList();
    return AlertDialog(
      title: Text('${m.index + 1}. ${m.title}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (m.subtitle.isNotEmpty)
                Text(
                  m.subtitle,
                  style: const TextStyle(color: Color(0xFFFFD35A)),
                ),
              const SizedBox(height: 8),
              for (final p in m.briefing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(p),
                ),
              const Divider(),
              const Text(
                'Objectifs',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final o in visible)
                Text('• ${o.label}${o.optional ? ' (facultatif)' : ''}'),
              if (m.objectives.any((o) => o.hidden))
                const Text(
                  '• … et d’autres objectifs à découvrir',
                  style: TextStyle(color: Colors.white60),
                ),
              if (m.rewards.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Récompenses : ${<String>[
                    ...m.rewardUnits.map(S.unit),
                    ...m.rewardBuildings.map(S.building),
                  ].join(', ')}',
                ),
              ],
              if (rec != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Meilleur résultat : ${rec.stars} ★ en '
                  '${rec.bestSeconds ~/ 60} min '
                  '${(rec.bestSeconds % 60).toString().padLeft(2, '0')} s '
                  '(${S.difficulties[rec.difficulty]})',
                  style: const TextStyle(color: Color(0xFFFFD35A)),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Difficulté',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  for (var i = 0; i < S.difficulties.length; i++)
                    ButtonSegment<int>(
                      value: i,
                      label: Text(S.difficulties[i]),
                    ),
                ],
                selected: <int>{difficulty},
                onSelectionChanged: (s) => setState(() => difficulty = s.first),
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
          onPressed: () => Navigator.of(context).pop(difficulty),
          child: Text(rec == null ? 'Commencer' : 'Rejouer'),
        ),
      ],
    );
  }
}
