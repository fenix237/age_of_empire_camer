import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/rng.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Générateur de commandes aléatoires (valides ou non) pour les tests de
/// propriétés, la simulation de masse et les outils de rejeu.
class CommandFuzzer {
  CommandFuzzer(int seed) : rng = Rng(seed);

  final Rng rng;

  T _pick<T>(List<T> l) => l[rng.nextInt(l.length)];

  /// Identifiants d'entités (parfois invalides, volontairement).
  int _anyId(World w) {
    final r = rng.nextInt(100);
    if (r < 6) return rng.range(-5, 99999);
    final pools = <Iterable<int>>[w.units.keys, w.buildings.keys, w.nodes.keys];
    final pool = _pick(pools).toList();
    if (pool.isEmpty) return rng.range(1, 50);
    return _pick(pool);
  }

  List<int> _units(World w, int owner) {
    final mine = <int>[
      for (final u in w.units.values)
        if (u.owner == owner) u.id,
    ];
    if (mine.isEmpty) return <int>[rng.range(1, 30)];
    final n = rng.range(1, mine.length < 14 ? mine.length : 14);
    final out = <int>[];
    for (var i = 0; i < n; i++) {
      out.add(_pick(mine));
    }
    if (rng.chance(3)) out.add(rng.range(0, 999));
    return out;
  }

  Command next(World w) {
    final owner = rng.chance(2)
        ? rng.range(-1, w.players.length + 1)
        : rng.nextInt(w.players.length);
    final defs = w.defs;
    final size = w.map.width;
    int coord() => rng.chance(4) ? rng.range(-3, size + 3) : rng.nextInt(size);
    final bs = <Building>[
      for (final b in w.buildings.values)
        if (b.owner == owner) b,
    ];
    int bid() => bs.isNotEmpty && rng.chance(90) ? _pick(bs).id : _anyId(w);
    int nodeId() => w.nodes.isNotEmpty && rng.chance(85)
        ? _pick(w.nodes.keys.toList())
        : _anyId(w);
    int near(int c) =>
        rng.chance(30) ? coord() : (c + rng.range(-10, 10)).clamp(0, size - 1);
    final home = owner >= 0 && owner < w.players.length
        ? w.players[owner]
        : null;
    if (rng.chance(10)) {
      final j = rng.nextInt(100);
      if (j < 55) {
        final mine = _units(w, owner);
        return PowerCmd(
          owner,
          mine.isEmpty ? -1 : _pick(mine),
          rng.range(-1, 3),
          x: coord(),
          y: coord(),
          target: _anyId(w),
        );
      }
      if (j < 80) {
        return SpellCmd(
          owner,
          rng.range(-1, defs.powers.length + 1),
          coord(),
          coord(),
        );
      }
      if (j < 99) return AgeUpCmd(owner, bid());
      return ResignCmd(owner);
    }
    final k = rng.nextInt(100);
    if (k < 22) {
      return MoveCmd(
        owner,
        _units(w, owner),
        coord(),
        coord(),
        queue: rng.chance(20),
      );
    }
    if (k < 38) {
      return GatherCmd(
        owner,
        _units(w, owner),
        nodeId(),
        queue: rng.chance(15),
      );
    }
    if (k < 44) {
      return AttackCmd(
        owner,
        _units(w, owner),
        _anyId(w),
        queue: rng.chance(15),
      );
    }
    if (k < 56) {
      final bd = _pick(defs.buildings);
      return BuildCmd(
        owner,
        _units(w, owner),
        bd.id,
        near(home?.startX ?? 0),
        near(home?.startY ?? 0),
        queue: rng.chance(10),
      );
    }
    if (k < 62) return RepairCmd(owner, _units(w, owner), bid());
    if (k < 66) return GarrisonCmd(owner, _units(w, owner), bid());
    if (k < 68) return UngarrisonCmd(owner, bid());
    if (k < 71) return StopCmd(owner, _units(w, owner));
    if (k < 73) {
      return SetStanceCmd(owner, _units(w, owner), _pick(Stance.values));
    }
    if (k < 84) {
      return TrainCmd(
        owner,
        bid(),
        _pick(defs.units).id,
        count: rng.range(1, 4),
      );
    }
    if (k < 88) return ResearchCmd(owner, bid(), _pick(defs.techs).id);
    if (k < 91) return CancelQueueCmd(owner, bid(), rng.range(-1, 5));
    if (k < 94) {
      return SetRallyCmd(
        owner,
        bid(),
        coord(),
        coord(),
        rng.chance(50) ? _anyId(w) : -1,
      );
    }
    if (k < 96) return DeleteCmd(owner, rng.chance(70) ? bid() : _anyId(w));
    if (k < 98) {
      return ExchangeCmd(
        owner,
        _pick(Res.values),
        _pick(Res.values),
        rng.range(-10, 400),
      );
    }
    return ReseedCmd(owner, bid());
  }
}

/// Résultat d'une simulation aléatoire.
class SimResult {
  SimResult(this.world, this.finalHash, this.hashes, this.violations);

  final World world;
  final int finalHash;
  final List<int> hashes;
  final List<String> violations;
}

/// Joue une partie [ticks] ticks avec des commandes aléatoires (toutes les
/// [cmdEvery] ticks), de façon entièrement déterministe depuis [seed].
SimResult simulateRandomGame(
  Defs defs, {
  required int seed,
  required int ticks,
  int size = 48,
  int players = 2,
  int cmdEvery = 5,
  bool checkInvariants = false,
}) {
  final w = createGame(defs, seed: seed, size: size, players: players)
    ..checkInvariantsEachTick = checkInvariants;
  final fuzz = CommandFuzzer(seed ^ 0x5DEECE66D);
  for (var t = 0; t < ticks; t++) {
    if (t % cmdEvery == 0) {
      final n = fuzz.rng.range(1, 3);
      for (var i = 0; i < n; i++) {
        w.submit(fuzz.next(w));
      }
    }
    w.step();
  }
  return SimResult(
    w,
    w.stateHash(),
    List<int>.of(w.hashLog),
    List<String>.of(w.violations),
  );
}
