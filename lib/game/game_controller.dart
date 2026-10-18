import 'dart:async';
import 'dart:ui';

import 'package:age_of_empire_camer/game/camera.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/render/assets.dart';
import 'package:age_of_empire_camer/game/render/world_renderer.dart';
import 'package:age_of_empire_camer/game/selection.dart';
import 'package:age_of_empire_camer/meta/save_store.dart';
import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/commands/contextual.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/construction.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter/foundation.dart';

/// Alerte affichée dans le HUD (attaque, bâtiment terminé…).
class GameAlert {
  GameAlert(this.kind, this.tileX, this.tileY, this.time, [this.detail = '']);

  final EventType kind;
  final int tileX;
  final int tileY;
  final double time;
  final String detail;
}

/// Notifie à chaque image de rendu (60 Hz) : mini-carte, effets continus.
/// Le HUD, lui, n'écoute que le contrôleur (changements d'état, 10 Hz).
class FrameClock extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Pont entre la simulation, le rendu et l'interface.
///
/// L'interface ne modifie jamais l'état : tout passe par des commandes
/// soumises à la simulation (règle transversale n°2).
class GameController extends ChangeNotifier {
  GameController({
    required this.world,
    required this.defs,
    this.localPlayer = 0,
    this.saveStore,
    AssetRegistry? assets,
  }) : assets = assets ?? AssetRegistry.placeholders(defs),
       camera = GameCamera(
         mapWidth: world.map.width,
         mapHeight: world.map.height,
       ) {
    renderer = WorldRenderer(world: world, assets: this.assets);
    final start = world.players[localPlayer];
    camera.centerOnTile(start.startX + 0.5, start.startY + 0.5);
  }

  final World world;
  final Defs defs;
  final int localPlayer;
  final SaveStore? saveStore;
  final AssetRegistry assets;
  final GameCamera camera;
  late final WorldRenderer renderer;
  final GameLoop loop = GameLoop();
  final SelectionModel selection = SelectionModel();
  final DebugOptions debug = DebugOptions();

  /// Horloge d'images de rendu (voir [FrameClock]).
  final FrameClock frameClock = FrameClock();

  final List<OrderMarker> markers = <OrderMarker>[];
  final List<GameAlert> alerts = <GameAlert>[];

  /// Temps réel écoulé depuis le début (animations, marqueurs).
  double time = 0;

  /// Bâtiment en cours de placement (mode construction) et son aperçu.
  BuildingDef? placing;
  int ghostX = 0;
  int ghostY = 0;
  bool ghostValid = false;

  /// Dernier message de refus d'une commande (affiché brièvement).
  String? lastRejection;
  double _rejectionAt = -10;

  /// Dernière sauvegarde automatique (temps réel).
  double _lastAutosave = 0;
  static const double autosaveSeconds = 120;

  /// Brouillard actif (désactivable en debug).
  bool fogEnabled = true;

  /// Mode « sélection multiple » tactile : le glisser trace un rectangle.
  bool multiSelectMode = false;

  /// Mode « file » tactile (équivalent de Maj+clic droit) : les ordres
  /// suivants s'ajoutent à la file de l'unité au lieu de la remplacer.
  bool queueMode = false;

  /// Mode attente de confirmation de suppression d'un bâtiment.
  int pendingDelete = -1;

  // ───────────────────────── Boucle ─────────────────────────

  /// Appelé à chaque frame de rendu avec le temps réel écoulé.
  void frame(double dt, {Offset keyboardPan = Offset.zero}) {
    time += dt;
    camera.update(dt, keyboard: keyboardPan);
    final n = loop.advance(dt);
    for (var i = 0; i < n; i++) {
      world.step();
      _consumeEvents();
    }
    if (n > 0) selection.prune(world);
    markers.removeWhere((m) => time - m.start > OrderMarker.duration);
    alerts.removeWhere((a) => time - a.time > 8);
    if (placing != null) _refreshGhost();
    if (saveStore != null && time - _lastAutosave > autosaveSeconds) {
      _lastAutosave = time;
      unawaited(autosave());
    }
    // Le HUD ne se reconstruit qu'à chaque tick de simulation (10 Hz) ou
    // lorsqu'une animation d'interface est en cours ; la mini-carte suit la
    // caméra à chaque image via [frameClock].
    if (n > 0 || placing != null || markers.isNotEmpty) notifyListeners();
    frameClock.tick();
  }

  void _consumeEvents() {
    for (final e in world.events) {
      if (e.owner != localPlayer && e.type != EventType.resourceDepleted) {
        continue;
      }
      switch (e.type) {
        case EventType.underAttack:
          final last = alerts.where((a) => a.kind == EventType.underAttack);
          if (last.isEmpty || time - last.last.time > 4) {
            alerts.add(GameAlert(e.type, e.x, e.y, time));
          }
        case EventType.buildingComplete:
        case EventType.unitTrained:
        case EventType.researchDone:
        case EventType.buildingDestroyed:
        case EventType.unitDied:
          alerts.add(GameAlert(e.type, e.x, e.y, time));
        case EventType.commandRejected:
          lastRejection = CmdResult.values[e.id].name;
          _rejectionAt = time;
        case EventType.resourceDepleted:
          break;
      }
    }
    if (time - _rejectionAt > 3) lastRejection = null;
  }

  // ───────────────────────── Pause / vitesse ─────────────────────────

  void pause(PauseReason r) {
    loop.pause(r);
    notifyListeners();
  }

  void resume(PauseReason r) {
    loop.resume(r);
    notifyListeners();
  }

  void togglePause() {
    loop.toggleUserPause();
    notifyListeners();
  }

  // ───────────────────────── Sélection ─────────────────────────

  PickResult pick(Offset screen, {bool touch = false}) => pickAt(
    world,
    camera,
    screen,
    tolerance: touch ? 28 : 22,
    preferOwner: localPlayer,
  );

  /// Clic/appui de sélection. Renvoie ce qui a été désigné.
  PickResult selectAt(
    Offset screen, {
    bool add = false,
    bool touch = false,
    bool doubleClick = false,
  }) {
    final r = pick(screen, touch: touch);
    switch (r.kind) {
      case PickKind.unit:
        final u = world.units[r.id]!;
        if (u.owner != localPlayer) {
          // Unité adverse : on la sélectionne seule pour information.
          selection.selectUnits(<int>[u.id]);
        } else if (doubleClick) {
          selection.selectUnits(
            selection.sameTypeVisible(world, camera, u),
            add: add,
          );
        } else if (add) {
          selection.toggleUnit(u.id);
        } else {
          selection.selectUnits(<int>[u.id]);
        }
      case PickKind.building:
        selection.selectBuilding(r.id);
      case PickKind.resource:
        selection.clear();
      case PickKind.none:
        if (!add) selection.clear();
    }
    notifyListeners();
    return r;
  }

  void selectRect(Rect screenRect, {bool add = false}) {
    final ids = unitsInScreenRect(world, camera, screenRect, localPlayer);
    if (ids.isEmpty) {
      if (!add) selection.clear();
    } else {
      selection.selectUnits(ids, add: add);
    }
    notifyListeners();
  }

  void controlGroup(int n, {required bool assign}) {
    if (assign) {
      selection.setGroup(n);
    } else if (selection.recallGroup(n, world)) {
      centerOnSelection();
    }
    notifyListeners();
  }

  void selectNextIdleVillager() {
    final u = selection.nextIdleVillager(world, localPlayer);
    if (u == null) return;
    selection.selectUnits(<int>[u.id]);
    camera.centerOn(Iso.fromFixed(u.x, u.y));
    notifyListeners();
  }

  int get idleVillagerCount => world.units.values
      .where(
        (u) => u.alive && u.owner == localPlayer && u.def.villager && u.isIdle,
      )
      .length;

  void centerOnSelection() {
    for (final id in selection.units) {
      final u = world.units[id];
      if (u != null) {
        camera.centerOn(Iso.fromFixed(u.x, u.y));
        return;
      }
    }
    final b = world.buildings[selection.building];
    if (b != null) camera.centerOn(Iso.fromFixed(b.center.x, b.center.y));
  }

  // ───────────────────────── Ordres ─────────────────────────

  void _send(Iterable<Command> cmds) => cmds.forEach(world.submit);

  /// Ordre contextuel (clic droit / appui sur la destination).
  void orderAt(Offset screen, {bool queue = false, bool touch = false}) {
    final r = pick(screen, touch: touch);
    final t = camera.screenToTile(screen);
    final tx = t.x.clamp(0, world.map.width - 1);
    final ty = t.y.clamp(0, world.map.height - 1);
    if (selection.building >= 0) {
      final b = world.buildings[selection.building];
      if (b != null && b.owner == localPlayer) {
        _send(<Command>[
          rallyCommand(
            world,
            localPlayer,
            b.id,
            tx: tx,
            ty: ty,
            targetId: r.kind == PickKind.resource ? r.id : -1,
          ),
        ]);
        _marker(tx, ty, const Color(0xFFFFE066));
      }
      return;
    }
    final cmds = contextualCommands(
      world,
      localPlayer,
      selection.units,
      tx: tx,
      ty: ty,
      targetId: r.kind == PickKind.none ? -1 : r.id,
      queue: queue || queueMode,
    );
    if (cmds.isEmpty) return;
    _send(cmds);
    final enemy = cmds.first is AttackCmd;
    _marker(tx, ty, enemy ? const Color(0xFFFF5050) : const Color(0xFF9BE8A8));
  }

  /// Ordre vers une case précise (clic droit sur la mini-carte).
  void orderAtTile(int tx, int ty, {bool queue = false}) {
    final x = tx.clamp(0, world.map.width - 1);
    final y = ty.clamp(0, world.map.height - 1);
    final id = entityAtTile(world, x, y);
    final cmds = contextualCommands(
      world,
      localPlayer,
      selection.units,
      tx: x,
      ty: y,
      targetId: id,
      queue: queue || queueMode,
    );
    if (cmds.isNotEmpty) {
      _send(cmds);
      _marker(x, y, const Color(0xFF9BE8A8));
    }
  }

  /// Active/désactive tout le mode debug (grille, occupation, chemins, stats).
  void setDebug({required bool enabled}) {
    debug
      ..grid = enabled
      ..occupancy = enabled
      ..paths = enabled
      ..stats = enabled;
    notifyListeners();
  }

  /// Demande un nouveau rendu (changement d'état provenant de l'interface).
  void refresh() => notifyListeners();

  void _marker(int tx, int ty, Color c) =>
      markers.add(OrderMarker(Iso.tileCenter(tx, ty), time, c));

  void stopSelected() {
    if (selection.units.isNotEmpty) {
      _send(<Command>[StopCmd(localPlayer, selection.units)]);
    }
  }

  void setStance(Stance s) {
    if (selection.units.isNotEmpty) {
      _send(<Command>[SetStanceCmd(localPlayer, selection.units, s)]);
    }
  }

  // ───────────────────────── Construction ─────────────────────────

  void startPlacement(BuildingDef def) {
    placing = def;
    selection.selectUnits(
      selection.units.where((id) => world.units[id]?.def.villager ?? false),
    );
    notifyListeners();
  }

  void cancelPlacement() {
    placing = null;
    notifyListeners();
  }

  /// Met à jour l'aperçu fantôme à partir de la position du pointeur.
  void updateGhost(Offset screen) {
    final def = placing;
    if (def == null) return;
    final t = camera.screenToTile(screen);
    ghostX = t.x - def.width ~/ 2;
    ghostY = t.y - def.height ~/ 2;
    _refreshGhost();
  }

  void _refreshGhost() {
    final def = placing;
    if (def == null) return;
    ghostValid =
        validatePlacement(world, localPlayer, def, ghostX, ghostY) ==
            CmdResult.ok &&
        world.players[localPlayer].stock.covers(def.cost);
  }

  PlacementGhost? get ghost {
    final def = placing;
    if (def == null) return null;
    return PlacementGhost(def, ghostX, ghostY, valid: ghostValid);
  }

  /// Valide le placement : envoie la commande de construction aux villageois
  /// sélectionnés (ou au plus proche si aucun). [keep] reste en mode pose.
  void confirmPlacement({bool keep = false}) {
    final def = placing;
    if (def == null) return;
    _refreshGhost();
    if (!ghostValid) {
      lastRejection = 'badPlacement';
      _rejectionAt = time;
      notifyListeners();
      return;
    }
    var builders = selection.units
        .where((id) => world.units[id]?.def.villager ?? false)
        .toList();
    if (builders.isEmpty) {
      final v = _nearestVillager(ghostX, ghostY);
      if (v != null) builders = <int>[v.id];
    }
    if (builders.isEmpty) {
      lastRejection = 'noUnits';
      _rejectionAt = time;
      notifyListeners();
      return;
    }
    _send(<Command>[
      BuildCmd(localPlayer, builders, def.id, ghostX, ghostY, queue: keep),
    ]);
    if (!keep) placing = null;
    notifyListeners();
  }

  Unit? _nearestVillager(int tx, int ty) {
    Unit? best;
    var bestD = 1 << 60;
    for (final u in world.units.values) {
      if (!u.alive || u.owner != localPlayer || !u.def.villager) continue;
      final dx = u.tileX - tx;
      final dy = u.tileY - ty;
      final d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        best = u;
      }
    }
    return best;
  }

  // ───────────────────────── Production / recherche ─────────────────────────

  Building? get selectedBuilding => world.buildings[selection.building];

  void train(String unitId, {int count = 1}) {
    final b = selectedBuilding;
    if (b == null) return;
    _send(<Command>[TrainCmd(localPlayer, b.id, unitId, count: count)]);
  }

  void research(String techId) {
    final b = selectedBuilding;
    if (b == null) return;
    _send(<Command>[ResearchCmd(localPlayer, b.id, techId)]);
  }

  void cancelQueue(int index) {
    final b = selectedBuilding;
    if (b == null) return;
    _send(<Command>[CancelQueueCmd(localPlayer, b.id, index)]);
  }

  void reseedSelected() {
    final b = selectedBuilding;
    if (b != null) _send(<Command>[ReseedCmd(localPlayer, b.id)]);
  }

  void ungarrisonSelected() {
    final b = selectedBuilding;
    if (b != null) _send(<Command>[UngarrisonCmd(localPlayer, b.id)]);
  }

  void exchange(Res from, Res to, int amount) =>
      _send(<Command>[ExchangeCmd(localPlayer, from, to, amount)]);

  /// Demande de suppression : confirmation obligatoire côté interface.
  void requestDelete() {
    final b = selectedBuilding;
    if (b == null || b.owner != localPlayer) return;
    pendingDelete = b.id;
    pause(PauseReason.dialog);
  }

  void confirmDelete() {
    if (pendingDelete >= 0) {
      _send(<Command>[DeleteCmd(localPlayer, pendingDelete)]);
    }
    pendingDelete = -1;
    resume(PauseReason.dialog);
  }

  void cancelDelete() {
    pendingDelete = -1;
    resume(PauseReason.dialog);
  }

  // ───────────────────────── Sauvegarde ─────────────────────────

  Future<void> autosave() async {
    final store = saveStore;
    if (store == null) return;
    try {
      await store.writeRotating('autosave', 3, world);
    } on Object catch (e) {
      debugPrint('Autosauvegarde impossible : $e');
    }
  }

  /// Sauvegarde manuelle ; renvoie false en cas d'échec (disque plein…).
  Future<bool> saveTo(String slot) async {
    final store = saveStore;
    if (store == null) return false;
    try {
      await store.saveWorld(slot, world);
      return true;
    } on Object catch (e) {
      debugPrint('Sauvegarde impossible : $e');
      return false;
    }
  }

  @override
  void dispose() {
    frameClock.dispose();
    renderer.dispose();
    super.dispose();
  }
}
