import 'package:age_of_empire_camer/sim/data/res.dart';

/// Définitions de gameplay (chargées depuis `assets/data/*.json`).
/// Aucune constante d'équilibrage ne doit vivre dans le code.

class TerrainDef {
  const TerrainDef({
    required this.id,
    required this.index,
    required this.walkable,
    required this.speedPercent,
    required this.moveCost,
    required this.buildable,
  });

  final String id;
  final int index;
  final bool walkable;

  /// Vitesse relative (100 = normale).
  final int speedPercent;

  /// Coût de traversée pour le pathfinding (10 = normal).
  final int moveCost;
  final bool buildable;
}

class ResourceDef {
  const ResourceDef({
    required this.id,
    required this.index,
    required this.res,
    required this.amount,
  });

  final String id;
  final int index;
  final Res res;
  final int amount;
}

class UnitDef {
  const UnitDef({
    required this.id,
    required this.index,
    required this.age,
    required this.cost,
    required this.trainSeconds,
    required this.hp,
    required this.attack,
    required this.armor,
    required this.range,
    required this.attackCooldownTicks,
    required this.speed,
    required this.vision,
    required this.pop,
    required this.villager,
    required this.carryCapacity,
    required this.gatherRates,
  });

  final String id;
  final int index;
  final int age;
  final Stock cost;
  final int trainSeconds;
  final int hp;
  final int attack;
  final int armor;

  /// Portée en cases (0 = mêlée).
  final int range;
  final int attackCooldownTicks;

  /// Vitesse en millièmes de case par seconde.
  final int speed;
  final int vision;
  final int pop;
  final bool villager;
  final int carryCapacity;

  /// Millièmes de ressource récoltés par seconde, par ressource.
  final Map<Res, int> gatherRates;

  bool get military => !villager && attack > 0;

  /// Déplacement par tick en virgule fixe (1 case = 256).
  int get speedFxPerTick => speed * 256 ~/ 10000;
}

class BuildingDef {
  const BuildingDef({
    required this.id,
    required this.index,
    required this.age,
    required this.width,
    required this.height,
    required this.cost,
    required this.buildSeconds,
    required this.hp,
    required this.armor,
    required this.vision,
    required this.popBonus,
    required this.dropOff,
    required this.trains,
    required this.researches,
    required this.garrison,
    required this.fieldFood,
    required this.requires,
    required this.market,
    required this.townCenter,
    required this.startsComplete,
  });

  final String id;
  final int index;
  final int age;
  final int width;
  final int height;
  final Stock cost;
  final int buildSeconds;
  final int hp;
  final int armor;
  final int vision;
  final int popBonus;
  final List<Res> dropOff;
  final List<String> trains;
  final List<String> researches;
  final int garrison;

  /// Nourriture d'un champ (0 = pas un champ).
  final int fieldFood;
  final List<String> requires;
  final bool market;
  final bool townCenter;
  final bool startsComplete;

  bool get isField => fieldFood > 0;
  int get buildTicks => buildSeconds * 10;
}

class AgeDef {
  const AgeDef({
    required this.id,
    required this.index,
    required this.cost,
    required this.researchSeconds,
    required this.requiresBuildings,
  });

  final String id;
  final int index;
  final Stock cost;
  final int researchSeconds;
  final List<String> requiresBuildings;
}

/// Un effet de recherche : modifie une statistique du joueur.
class TechEffect {
  const TechEffect({
    required this.stat,
    required this.res,
    required this.add,
    required this.percent,
  });

  /// `carry` (capacité de portage) ou `gather` (vitesse de récolte).
  final String stat;
  final Res? res;
  final int add;
  final int percent;
}

class TechDef {
  const TechDef({
    required this.id,
    required this.index,
    required this.age,
    required this.cost,
    required this.researchSeconds,
    required this.effects,
  });

  final String id;
  final int index;
  final int age;
  final Stock cost;
  final int researchSeconds;
  final List<TechEffect> effects;
}

/// Constantes globales d'équilibrage et de réglage du moteur.
class BalanceDef {
  const BalanceDef({
    required this.startingResources,
    required this.startingVillagers,
    required this.maxPopulation,
    required this.maxQueue,
    required this.buildSpeedMilli,
    required this.repairCostPercent,
    required this.repairSpeedPercent,
    required this.marketFeePercent,
    required this.pathRequestsPerTick,
    required this.pathNodeLimit,
    required this.stuckReplanTicks,
    required this.stuckTeleportTicks,
    required this.flowFieldGroupMin,
    required this.separationRadius,
    required this.idleSearchRadius,
    required this.fieldGatherers,
    required this.reseedCostWood,
    required this.queueRefundPercent,
    required this.vision,
    required this.hashEveryTicks,
    required this.visionEveryTicks,
    required this.mapGen,
  });

  final Stock startingResources;
  final int startingVillagers;
  final int maxPopulation;
  final int maxQueue;

  /// Multiplicateur de vitesse de construction (milli) selon le nombre de
  /// bâtisseurs (index = nombre ; dernier élément réutilisé au-delà).
  final List<int> buildSpeedMilli;
  final int repairCostPercent;
  final int repairSpeedPercent;
  final int marketFeePercent;
  final int pathRequestsPerTick;
  final int pathNodeLimit;
  final int stuckReplanTicks;
  final int stuckTeleportTicks;
  final int flowFieldGroupMin;

  /// Rayon de séparation entre unités, en virgule fixe.
  final int separationRadius;
  final int idleSearchRadius;
  final int fieldGatherers;
  final int reseedCostWood;
  final int queueRefundPercent;
  final int vision;
  final int hashEveryTicks;
  final int visionEveryTicks;
  final MapGenDef mapGen;
}

class MapGenDef {
  const MapGenDef({
    required this.baseClearRadius,
    required this.playerRingPercent,
    required this.noiseScale,
    required this.waterLevel,
    required this.deepWaterLevel,
    required this.mountainLevel,
    required this.forestThreshold,
    required this.treesPerStartForest,
    required this.startForests,
    required this.startBerries,
    required this.startStone,
    required this.startIron,
    required this.startGold,
    required this.startGame,
    required this.scatterPerThousand,
    required this.maxAttempts,
  });

  final int baseClearRadius;

  /// Distance des départs au centre, en % du demi-côté.
  final int playerRingPercent;
  final int noiseScale;
  final int waterLevel;
  final int deepWaterLevel;
  final int mountainLevel;
  final int forestThreshold;
  final int treesPerStartForest;
  final int startForests;
  final int startBerries;
  final int startStone;
  final int startIron;
  final int startGold;
  final int startGame;
  final int scatterPerThousand;
  final int maxAttempts;
}
