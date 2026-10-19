import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/render/assets.dart';
import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/construction.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:age_of_empire_camer/ui/hud/combat_hud.dart';
import 'package:age_of_empire_camer/ui/hud/minimap.dart';
import 'package:age_of_empire_camer/ui/responsive/size_class.dart';
import 'package:age_of_empire_camer/ui/strings.dart';
import 'package:flutter/material.dart';

/// Dimensions du HUD selon la classe de taille (téléphone / tablette / PC).
class HudMetrics {
  const HudMetrics(this.sizeClass, {this.textScale = 1, this.width = 1280});

  final SizeClass sizeClass;

  /// Échelle de texte / d'interface (80–150 %) : les hauteurs la suivent pour
  /// que rien ne déborde.
  final double textScale;

  /// Largeur disponible (dp).
  final double width;

  bool get compact => sizeClass == SizeClass.compact;
  bool get narrow => width < 520;
  double get _k => textScale.clamp(1.0, 1.5);
  double get button => sizeClass.minTouchTarget;
  double get topBar => (compact ? 44 : 40) * _k;
  double get bottomHeight =>
      (compact ? 112 : (sizeClass == SizeClass.medium ? 140 : 160)) * _k;
  double get miniMap {
    final base = compact
        ? 130.0
        : (sizeClass == SizeClass.medium ? 170.0 : 210.0);
    return base.clamp(80.0, width * 0.32);
  }

  double get font => compact ? 12 : 13;
}

IconData resIcon(Res r) => switch (r) {
  Res.food => Icons.restaurant,
  Res.wood => Icons.park,
  Res.stone => Icons.landscape,
  Res.iron => Icons.hardware,
  Res.gold => Icons.savings,
};

/// HUD complet superposé à la vue de jeu. Les widgets ne modifient jamais la
/// simulation : ils appellent des méthodes du [GameController] qui émettent
/// des commandes.
class Hud extends StatelessWidget {
  const Hud({required this.controller, required this.onMenu, super.key});

  final GameController controller;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, sizeClass) {
        final m = HudMetrics(
          sizeClass,
          textScale: MediaQuery.textScalerOf(context).scale(1),
          width: MediaQuery.sizeOf(context).width,
        );
        return SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TopBar(
                  controller: controller,
                  metrics: m,
                  onMenu: onMenu,
                ),
              ),
              Positioned(
                left: 8,
                top: m.topBar + 8,
                child: AlertFeed(controller: controller, metrics: m),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: m.topBar + 4,
                child: Center(child: _Toast(controller: controller)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BottomBar(controller: controller, metrics: m),
              ),
              Positioned(
                right: 8,
                bottom: m.bottomHeight + 4,
                child: CombatPanel(controller: controller, metrics: m),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: m.topBar + 44,
                child: Center(child: TargetingBanner(controller: controller)),
              ),
              if (controller.placing != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: m.bottomHeight + 12,
                  child: Center(
                    child: _PlacementButtons(
                      controller: controller,
                      metrics: m,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Barre du haut ─────────────────────────

class TopBar extends StatelessWidget {
  const TopBar({
    required this.controller,
    required this.metrics,
    required this.onMenu,
    super.key,
  });

  final GameController controller;
  final HudMetrics metrics;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final p = controller.world.players[controller.localPlayer];
        final loop = controller.loop;
        return Container(
          height: metrics.topBar,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: const Color(0xCC1B1410),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final r in Res.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _ResourceChip(
                            icon: resIcon(r),
                            color: resourceColor(r),
                            value: p.stock[r],
                            tooltip: S.res(r),
                            font: metrics.font,
                          ),
                        ),
                      _PopChip(
                        used: p.popUsed,
                        cap: p.popCap,
                        font: metrics.font,
                      ),
                    ],
                  ),
                ),
              ),
              if (!metrics.compact)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    S.age(p.age),
                    style: TextStyle(
                      fontSize: metrics.font,
                      color: Colors.white70,
                    ),
                  ),
                ),
              _IdleButton(controller: controller, metrics: metrics),
              IconButton(
                tooltip: loop.paused ? S.resume : S.pause,
                onPressed: controller.togglePause,
                icon: Icon(loop.paused ? Icons.play_arrow : Icons.pause),
              ),
              TextButton(
                onPressed: () {
                  loop.cycleSpeed();
                  controller.refresh();
                },
                child: Text(
                  '×${loop.speed == loop.speed.roundToDouble() ? loop.speed.round() : loop.speed}',
                ),
              ),
              IconButton(
                tooltip: S.menu,
                onPressed: onMenu,
                icon: const Icon(Icons.menu),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResourceChip extends StatelessWidget {
  const _ResourceChip({
    required this.icon,
    required this.color,
    required this.value,
    required this.tooltip,
    required this.font,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String tooltip;
  final double font;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: font + 5, color: color),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: font + 1,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PopChip extends StatelessWidget {
  const _PopChip({required this.used, required this.cap, required this.font});

  final int used;
  final int cap;
  final double font;

  @override
  Widget build(BuildContext context) {
    final full = used >= cap;
    return Tooltip(
      message: 'Population',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.groups,
            size: font + 5,
            color: full ? Colors.redAccent : Colors.white70,
          ),
          const SizedBox(width: 4),
          Text(
            '$used/$cap',
            style: TextStyle(
              fontSize: font + 1,
              color: full ? Colors.redAccent : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdleButton extends StatelessWidget {
  const _IdleButton({required this.controller, required this.metrics});

  final GameController controller;
  final HudMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final n = controller.idleVillagerCount;
    return Tooltip(
      message: '${S.idleVillagers} (.)',
      child: TextButton.icon(
        onPressed: n == 0 ? null : controller.selectNextIdleVillager,
        icon: Icon(
          Icons.person_off,
          color: n > 0 ? Colors.amber : Colors.white38,
        ),
        label: Text(
          '$n',
          style: TextStyle(color: n > 0 ? Colors.amber : Colors.white38),
        ),
      ),
    );
  }
}

// ───────────────────────── Alertes ─────────────────────────

class AlertFeed extends StatelessWidget {
  const AlertFeed({required this.controller, required this.metrics, super.key});

  final GameController controller;
  final HudMetrics metrics;

  static String _text(GameAlert a) => switch (a.kind) {
    EventType.underAttack => 'Nous sommes attaqués !',
    EventType.buildingComplete => 'Bâtiment terminé',
    EventType.unitTrained => 'Unité prête',
    EventType.researchDone => 'Recherche terminée',
    EventType.buildingDestroyed => 'Bâtiment détruit',
    EventType.unitDied => 'Unité perdue',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final recent = controller.alerts.reversed.take(4).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final a in recent)
              if (_text(a).isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: a.kind == EventType.underAttack
                        ? const Color(0xCCB02020)
                        : const Color(0xAA1B1410),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _text(a),
                    style: TextStyle(
                      fontSize: metrics.font,
                      color: Colors.white,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final msg = controller.lastRejection;
        if (msg == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xDD7A1E1E),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            S.rejection(msg),
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
    );
  }
}

// ───────────────────────── Barre du bas ─────────────────────────

class BottomBar extends StatelessWidget {
  const BottomBar({required this.controller, required this.metrics, super.key});

  final GameController controller;
  final HudMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: metrics.bottomHeight,
      color: const Color(0xDD1B1410),
      padding: const EdgeInsets.all(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: MiniMap(controller: controller, size: metrics.miniMap),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: SelectionPanel(controller: controller, metrics: metrics),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: metrics.compact ? 5 : 4,
            child: ActionPanel(controller: controller, metrics: metrics),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Sélection ─────────────────────────

class SelectionPanel extends StatelessWidget {
  const SelectionPanel({
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
        final w = controller.world;
        final sel = controller.selection;
        final style = TextStyle(color: Colors.white, fontSize: metrics.font);
        if (sel.building >= 0) {
          final b = w.buildings[sel.building];
          if (b == null) return const SizedBox.shrink();
          return _BuildingInfo(
            controller: controller,
            building: b,
            metrics: metrics,
          );
        }
        final units = <Unit>[
          for (final id in sel.units)
            if (w.units[id] != null) w.units[id]!,
        ];
        if (units.isEmpty) {
          return Center(
            child: Text(
              metrics.compact
                  ? 'Touchez une unité'
                  : 'Cliquez sur une unité ou un bâtiment',
              style: style.copyWith(color: Colors.white38),
            ),
          );
        }
        if (units.length == 1) {
          return _UnitInfo(unit: units.first, metrics: metrics);
        }
        // Regroupement par type.
        final counts = <String, int>{};
        for (final u in units) {
          counts[u.def.id] = (counts[u.def.id] ?? 0) + 1;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${units.length} unités sélectionnées', style: style),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final e in counts.entries)
                      Chip(
                        label: Text('${S.unit(e.key)} × ${e.value}'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UnitInfo extends StatelessWidget {
  const _UnitInfo({required this.unit, required this.metrics});

  final Unit unit;
  final HudMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: Colors.white, fontSize: metrics.font);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            S.unit(unit.def.id),
            style: style.copyWith(
              fontSize: metrics.font + 3,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text('PV ${unit.hp}/${unit.def.hp}', style: style),
          Text(S.unitState(unit), style: style.copyWith(color: Colors.white70)),
          if (unit.carryAmt > 0 && unit.carryType != null)
            Text(
              'Porte ${unit.carryAmt} ${S.res(unit.carryType!).toLowerCase()}',
              style: style.copyWith(color: Colors.white70),
            ),
          if (unit.def.attack > 0)
            Text(
              'Attaque ${unit.def.attack}  Armure ${unit.def.armor}',
              style: style.copyWith(color: Colors.white54),
            ),
        ],
      ),
    );
  }
}

class _BuildingInfo extends StatelessWidget {
  const _BuildingInfo({
    required this.controller,
    required this.building,
    required this.metrics,
  });

  final GameController controller;
  final Building building;
  final HudMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final b = building;
    final style = TextStyle(color: Colors.white, fontSize: metrics.font);
    final defs = controller.defs;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            S.building(b.def.id),
            style: style.copyWith(
              fontSize: metrics.font + 3,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text('PV ${b.hp}/${b.maxHp}', style: style),
          if (!b.complete)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: b.progressMilli / b.totalBuildMilli,
                minHeight: 6,
              ),
            ),
          if (b.isField)
            Text(
              'Reste ${b.stock} nourriture',
              style: style.copyWith(color: Colors.white70),
            ),
          if (b.garrisoned.isNotEmpty)
            Text(
              'Garnison : ${b.garrisoned.length}/${b.def.garrison}',
              style: style.copyWith(color: Colors.white70),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var i = 0; i < b.queue.length; i++)
                _QueueCard(
                  controller: controller,
                  item: b.queue[i],
                  index: i,
                  defs: defs,
                  metrics: metrics,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.controller,
    required this.item,
    required this.index,
    required this.defs,
    required this.metrics,
  });

  final GameController controller;
  final QueueItem item;
  final int index;
  final Defs defs;
  final HudMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final q = item;
    final total = q.isTech
        ? defs.techs[q.defIndex].researchSeconds * 10
        : defs.units[q.defIndex].trainSeconds * 10;
    final name = q.isTech
        ? S.tech(defs.techs[q.defIndex].id)
        : S.unit(defs.units[q.defIndex].id);
    return SizedBox(
      width: 96,
      child: Card(
        color: index == 0 ? const Color(0xFF4A3524) : const Color(0xFF2E2118),
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => controller.cancelQueue(index),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: metrics.font - 1,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: index == 0 ? 1 - q.remaining / total : 0,
                  minHeight: 4,
                ),
                const Icon(Icons.close, size: 12, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Actions ─────────────────────────

class ActionPanel extends StatelessWidget {
  const ActionPanel({
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
        final w = controller.world;
        final sel = controller.selection;
        final p = w.players[controller.localPlayer];
        final buttons = <Widget>[];

        if (sel.building >= 0) {
          final b = w.buildings[sel.building];
          if (b != null && b.owner == controller.localPlayer) {
            if (b.complete) {
              for (final uid in b.def.trains) {
                final def = controller.defs.unit(uid);
                buttons.add(
                  _ActionButton(
                    label: S.unit(uid),
                    cost: def.cost,
                    enabled: p.stock.covers(def.cost) && def.age <= p.age,
                    icon: Icons.person_add,
                    metrics: metrics,
                    onTap: () => controller.train(uid),
                  ),
                );
              }
              for (final tid in b.def.researches) {
                final def = controller.defs.tech(tid);
                if (p.hasTech(def.index)) continue;
                buttons.add(
                  _ActionButton(
                    label: S.tech(tid),
                    cost: def.cost,
                    enabled: p.stock.covers(def.cost) && def.age <= p.age,
                    icon: Icons.science,
                    metrics: metrics,
                    onTap: () => controller.research(tid),
                  ),
                );
              }
              if (b.isField && b.stock == 0) {
                buttons.add(
                  _ActionButton(
                    label: S.reseed,
                    icon: Icons.grass,
                    enabled:
                        p.stock[Res.wood] >=
                        controller.defs.balance.reseedCostWood,
                    metrics: metrics,
                    onTap: controller.reseedSelected,
                  ),
                );
              }
              if (b.garrisoned.isNotEmpty) {
                buttons.add(
                  _ActionButton(
                    label: S.ungarrison,
                    icon: Icons.logout,
                    metrics: metrics,
                    onTap: controller.ungarrisonSelected,
                  ),
                );
              }
              if (b.def.market) {
                buttons.add(
                  _ActionButton(
                    label: S.market,
                    icon: Icons.swap_horiz,
                    metrics: metrics,
                    onTap: () => showMarketDialog(context, controller),
                  ),
                );
              }
            }
            buttons.add(
              _ActionButton(
                label: b.complete ? S.deleteBuilding : S.cancel,
                icon: Icons.delete_outline,
                metrics: metrics,
                danger: true,
                onTap: controller.requestDelete,
              ),
            );
          }
        } else {
          final units = <Unit>[
            for (final id in sel.units)
              if (w.units[id] != null) w.units[id]!,
          ];
          final hasVillager = units.any((u) => u.def.villager);
          final hasMilitary = units.any((u) => u.def.military);
          if (hasVillager) {
            for (final b in controller.defs.buildings) {
              if (b.townCenter && !b.startsComplete) continue;
              final unlocked = b.age <= p.age;
              final can = unlocked && p.stock.covers(b.cost);
              buttons.add(
                _ActionButton(
                  label: S.building(b.id),
                  cost: b.cost,
                  enabled: can,
                  icon: Icons.home_work,
                  selected: controller.placing?.id == b.id,
                  metrics: metrics,
                  onTap: () => controller.startPlacement(b),
                ),
              );
            }
          }
          if (hasMilitary) {
            for (final s in Stance.values) {
              buttons.add(
                _ActionButton(
                  label: S.stance(s),
                  icon: Icons.shield,
                  metrics: metrics,
                  onTap: () => controller.setStance(s),
                ),
              );
            }
          }
          if (units.isNotEmpty) {
            buttons.add(
              _ActionButton(
                label: S.stop,
                icon: Icons.stop,
                metrics: metrics,
                onTap: controller.stopSelected,
              ),
            );
          }
          if (metrics.compact && units.isNotEmpty) {
            buttons.add(
              _ActionButton(
                label: S.queue,
                icon: Icons.format_list_numbered,
                selected: controller.queueMode,
                metrics: metrics,
                onTap: () {
                  controller.queueMode = !controller.queueMode;
                  controller.refresh();
                },
              ),
            );
          }
          if (metrics.compact) {
            buttons.add(
              _ActionButton(
                label: S.multiSelect,
                icon: Icons.select_all,
                selected: controller.multiSelectMode,
                metrics: metrics,
                onTap: () {
                  controller.multiSelectMode = !controller.multiSelectMode;
                  controller.refresh();
                },
              ),
            );
          }
        }

        if (buttons.isEmpty) return const SizedBox.shrink();
        return SingleChildScrollView(
          child: Wrap(spacing: 6, runSpacing: 6, children: buttons),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.metrics,
    required this.onTap,
    this.cost,
    this.enabled = true,
    this.selected = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final HudMetrics metrics;
  final VoidCallback onTap;
  final Stock? cost;
  final bool enabled;
  final bool selected;
  final bool danger;

  String get _costText {
    final c = cost;
    if (c == null) return '';
    final parts = <String>[
      for (final r in Res.values)
        if (c[r] > 0) '${c[r]} ${S.res(r).substring(0, 1).toLowerCase()}',
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? const Color(0xFF8A2A2A)
        : (selected ? const Color(0xFF8B5A2B) : const Color(0xFF3A2A1E));
    return Tooltip(
      message: _costText.isEmpty ? label : '$label — $_costText',
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: metrics.button + 18,
                minHeight: metrics.button,
                maxWidth: 104,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 16, color: Colors.white),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: metrics.font - 1,
                      ),
                    ),
                    if (_costText.isNotEmpty)
                      Text(
                        _costText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: metrics.font - 3,
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

class _PlacementButtons extends StatelessWidget {
  const _PlacementButtons({required this.controller, required this.metrics});

  final GameController controller;
  final HudMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        FloatingActionButton(
          heroTag: 'place_cancel',
          backgroundColor: const Color(0xFF8A2A2A),
          onPressed: controller.cancelPlacement,
          child: const Icon(Icons.close),
        ),
        const SizedBox(width: 12),
        FloatingActionButton(
          heroTag: 'place_ok',
          backgroundColor: controller.ghostValid
              ? const Color(0xFF2E8B4A)
              : Colors.grey,
          onPressed: controller.confirmPlacement,
          child: const Icon(Icons.check),
        ),
      ],
    );
  }
}

// ───────────────────────── Marché ─────────────────────────

Future<void> showMarketDialog(BuildContext context, GameController c) {
  return showDialog<void>(
    context: context,
    builder: (context) => _MarketDialog(controller: c),
  );
}

class _MarketDialog extends StatefulWidget {
  const _MarketDialog({required this.controller});

  final GameController controller;

  @override
  State<_MarketDialog> createState() => _MarketDialogState();
}

class _MarketDialogState extends State<_MarketDialog> {
  Res from = Res.wood;
  Res to = Res.gold;
  int amount = 100;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final fee = c.defs.balance.marketFeePercent;
    final got = amount * (100 - fee) ~/ 100;
    return AlertDialog(
      title: const Text('Marché'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('Donner '),
              DropdownButton<Res>(
                value: from,
                items: <DropdownMenuItem<Res>>[
                  for (final r in Res.values)
                    DropdownMenuItem<Res>(value: r, child: Text(S.res(r))),
                ],
                onChanged: (v) => setState(() => from = v ?? from),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const Text('Recevoir '),
              DropdownButton<Res>(
                value: to,
                items: <DropdownMenuItem<Res>>[
                  for (final r in Res.values)
                    DropdownMenuItem<Res>(value: r, child: Text(S.res(r))),
                ],
                onChanged: (v) => setState(() => to = v ?? to),
              ),
            ],
          ),
          Slider(
            min: 50,
            max: 500,
            divisions: 9,
            value: amount.toDouble(),
            label: '$amount',
            onChanged: (v) => setState(() => amount = v.round()),
          ),
          Text(
            '$amount ${S.res(from).toLowerCase()} → $got ${S.res(to).toLowerCase()} (frais $fee %)',
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        FilledButton(
          onPressed: from == to ? null : () => c.exchange(from, to, amount),
          child: const Text('Échanger'),
        ),
      ],
    );
  }
}

/// Dialogue de confirmation de suppression (action destructrice).
class DeleteConfirmation extends StatelessWidget {
  const DeleteConfirmation({required this.controller, super.key});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.pendingDelete < 0) return const SizedBox.shrink();
        final b = controller.world.buildings[controller.pendingDelete];
        return ColoredBox(
          color: Colors.black54,
          child: Center(
            child: AlertDialog(
              title: const Text(S.confirmDeleteTitle),
              content: Text(
                b == null
                    ? ''
                    : (b.complete
                          ? '${S.building(b.def.id)} sera détruit sans remboursement.'
                          : 'La construction sera annulée (remboursement du restant).'),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: controller.cancelDelete,
                  child: const Text(S.cancel),
                ),
                FilledButton(
                  onPressed: controller.confirmDelete,
                  child: const Text(S.confirm),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Aperçu de la validité d'un placement pour un bouton (infobulle).
CmdResult placementStatus(GameController c, BuildingDef def, int x, int y) =>
    validatePlacement(c.world, c.localPlayer, def, x, y);
