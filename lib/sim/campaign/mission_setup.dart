import 'package:age_of_empire_camer/sim/campaign/mission_def.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_runtime.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/systems/vision.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Crée la partie d'une mission : carte, joueurs, bases, déblocages de
/// campagne, entités posées et moteur de mission.
///
/// [unlocked] : identifiants débloqués par les récompenses des missions déjà
/// réussies (ils sortent de la liste des éléments verrouillés du joueur).
World createMissionGame(
  Defs defs,
  MissionDef m, {
  int difficulty = 1,
  Set<String> unlocked = const <String>{},
}) {
  final d = m.difficulties[difficulty.clamp(0, m.difficulties.length - 1)];
  final levels = defs.ai.difficulties.length;
  final setups = <PlayerSetup>[];
  for (var i = 0; i < m.players.length; i++) {
    final p = m.players[i];
    final clan = defs.clans.indexWhere((c) => c.id == p.clan);
    if (clan < 0) {
      throw DataException('campaign', m.id, 'clan inconnu « ${p.clan} »');
    }
    setups.add(
      PlayerSetup(
        clan: clan,
        aiLevel: p.ai < 0 ? -1 : (p.ai + d.aiLevel).clamp(0, levels - 1),
        team: p.team,
      ),
    );
  }
  final w = createGame(
    defs,
    seed: m.mapSeed,
    size: m.mapSize,
    players: m.players.length,
    style: m.mapStyle,
    setups: setups,
  );
  for (var i = 0; i < m.players.length; i++) {
    final def = m.players[i];
    final p = w.players[i]..age = def.age;
    if (def.resources != null) {
      p.stock = i == 0
          ? def.resources!.scaled(d.resourcePct, 100)
          : def.resources!.copy();
    } else if (i == 0) {
      p.stock = p.stock.scaled(d.resourcePct, 100);
    }
    if (!def.base) {
      for (final b in List.of(w.buildings.values)) {
        if (b.owner == i) w.removeBuilding(b, destroyed: false);
      }
      for (final u in List.of(w.units.values)) {
        if (u.owner == i) w.killUnit(u);
      }
    }
    if (i == 0) {
      p.locked
        ..addAll(def.lockedUnits)
        ..addAll(def.lockedBuildings)
        ..addAll(def.lockedTechs)
        ..removeAll(unlocked);
    }
  }
  final runtime = MissionRuntime(m, difficulty: difficulty);
  w.mission = runtime;
  for (final pl in m.placements) {
    final (x, y) = resolvePos(w, pl.at);
    final made = <int>[];
    if (pl.unit != null) {
      final def = defs.unit(pl.unit!);
      final used = <int>{};
      for (var k = 0; k < pl.count; k++) {
        final spot = freeTileNear(w, x, y, used);
        if (spot == null) break;
        used.add(w.map.index(spot.$1, spot.$2));
        made.add(
          w
              .spawnUnit(
                def,
                pl.owner,
                Fx.tileCenter(spot.$1),
                Fx.tileCenter(spot.$2),
              )
              .id,
        );
      }
    } else {
      for (var k = 0; k < pl.count; k++) {
        final b = placeBuildingNear(
          w,
          pl.owner,
          defs.building(pl.building!),
          x + k * 4,
          y,
          complete: pl.complete,
        );
        if (b != null) made.add(b.id);
      }
    }
    if (pl.tag != null) (runtime.tags[pl.tag!] ??= <int>[]).addAll(made);
  }
  w.recount();
  updateVision(w);
  return w;
}

/// Rattache la définition de mission à un monde chargé depuis une sauvegarde.
void attachMission(World w, CampaignDef campaign) {
  final raw = w.missionRaw;
  if (raw == null) return;
  final def = campaign.byId(raw['id'] as String);
  if (def == null) {
    throw DataException('campaign', raw['id'] as String, 'mission inconnue');
  }
  w
    ..mission = MissionRuntime.restore(def, raw)
    ..missionRaw = null;
}
