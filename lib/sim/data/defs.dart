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
    this.classes = const <String>{},
    this.pierceArmor = 0,
    this.damageType = DamageType.melee,
    this.bonus = const <String, int>{},
    this.projectileSpeed = 0,
    this.splash = 0,
    this.powers = const <String>[],
    this.clan = '',
    this.onHit,
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

  /// Catégories (`infantry`, `archer`, `cavalry`, `siege`, `hero`…) servant
  /// aux bonus de dégâts, aux recherches et aux clans.
  final Set<String> classes;

  /// Armure contre les attaques à distance (l'armure de base vaut en mêlée).
  final int pierceArmor;
  final DamageType damageType;

  /// Dégâts supplémentaires contre une catégorie (`building` inclus).
  final Map<String, int> bonus;

  /// Vitesse du projectile en millièmes de case par seconde (0 = mêlée).
  final int projectileSpeed;

  /// Rayon de dégâts de zone à l'impact, en millièmes de case.
  final int splash;

  /// Pouvoirs (identifiants) : le premier est le pouvoir de base, le second
  /// (héros) l'ultime.
  final List<String> powers;

  /// Clan exclusif (vide = tous les clans).
  final String clan;

  /// Effet appliqué à la cible touchée (coups qui ralentissent…).
  final EffectSpec? onHit;

  bool get military => !villager && attack > 0;
  bool get isHero => classes.contains('hero');
  bool get ranged => range > 0;

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
    this.pierceArmor = -1,
    this.attack = 0,
    this.range = 0,
    this.attackCooldownTicks = 20,
    this.projectileSpeed = 0,
    this.garrisonArrows = 0,
    this.classes = const <String>{},
    this.vital = true,
    this.agesUp = false,
    this.clan = '',
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

  /// Armure contre les projectiles ; -1 = armure de base + 5.
  final int pierceArmor;

  /// Attaque propre du bâtiment (tours, forteresse) ; 0 = aucune.
  final int attack;
  final int range;
  final int attackCooldownTicks;
  final int projectileSpeed;

  /// Flèches supplémentaires par unité militaire en garnison.
  final int garrisonArrows;
  final Set<String> classes;

  /// Compte pour la défaite : un joueur sans bâtiment vital est éliminé.
  final bool vital;

  /// Peut lancer les recherches de changement d'âge.
  final bool agesUp;
  final String clan;

  int get effectivePierceArmor => pierceArmor >= 0 ? pierceArmor : armor + 5;
  bool get isWall => classes.contains('wall');
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
    this.researchedAt = const <String>[],
  });

  final String id;
  final int index;
  final Stock cost;
  final int researchSeconds;
  final List<String> requiresBuildings;

  /// Bâtiments pouvant lancer cette recherche d'âge.
  final List<String> researchedAt;
}

/// Un effet de recherche : modifie une statistique du joueur.
class TechEffect {
  const TechEffect({
    required this.stat,
    required this.res,
    required this.add,
    required this.percent,
    this.cls = 'all',
  });

  /// `carry`, `gather`, `attack`, `armor`, `pierce_armor`, `hp`, `speed`,
  /// `range` (les derniers portent sur la catégorie [cls]).
  final String stat;
  final Res? res;
  final int add;
  final int percent;
  final String cls;

  static const Set<String> stats = <String>{
    'carry',
    'gather',
    'attack',
    'armor',
    'pierce_armor',
    'hp',
    'speed',
    'range',
  };
}

enum DamageType { melee, pierce, siege }

/// Effet temporaire sur une unité (pouvoirs, sorts, coups spéciaux).
enum EffectKind {
  stun,
  slow,
  root,
  speed,
  attackPct,
  armorAdd,
  gatherPct,
  firstHitPct,
  stunImmune,
  dot,
  heal,
  damage,
  purge,
}

const Map<String, EffectKind> effectKindByName = <String, EffectKind>{
  'stun': EffectKind.stun,
  'slow': EffectKind.slow,
  'root': EffectKind.root,
  'speed': EffectKind.speed,
  'attack_pct': EffectKind.attackPct,
  'armor_add': EffectKind.armorAdd,
  'gather_pct': EffectKind.gatherPct,
  'first_hit_pct': EffectKind.firstHitPct,
  'stun_immune': EffectKind.stunImmune,
  'dot': EffectKind.dot,
  'heal': EffectKind.heal,
  'damage': EffectKind.damage,
  'purge': EffectKind.purge,
};

class EffectSpec {
  const EffectSpec(this.kind, this.value, this.ticks);

  final EffectKind kind;

  /// Pourcentage, points d'armure, PV (heal/damage) ou PV par seconde (dot).
  final int value;
  final int ticks;
}

enum PowerTarget { self, unit, ground }

enum PowerAffects { allies, enemies, all }

/// Pouvoir d'unité ou sort de bataille (un sort a un [drumCost] > 0).
class PowerDef {
  const PowerDef({
    required this.id,
    required this.index,
    required this.age,
    required this.cooldownTicks,
    required this.target,
    required this.rangeTiles,
    required this.radius,
    required this.affects,
    required this.effects,
    required this.drumCost,
    required this.aura,
    required this.includeSelf,
  });

  final String id;
  final int index;

  /// Âge minimal du lanceur pour utiliser le pouvoir.
  final int age;
  final int cooldownTicks;
  final PowerTarget target;
  final int rangeTiles;

  /// Rayon de la zone en millièmes de case (0 = cible seule).
  final int radius;
  final PowerAffects affects;
  final List<EffectSpec> effects;

  /// Coût en énergie du tambour (sorts) ; 0 pour un pouvoir d'unité.
  final int drumCost;

  /// Aura : appliquée en permanence autour du porteur.
  final bool aura;
  final bool includeSelf;

  bool get isSpell => drumCost > 0;
}

class ClanDef {
  const ClanDef({
    required this.id,
    required this.index,
    required this.playable,
    required this.hero,
    required this.effects,
    required this.startBonus,
    required this.personality,
  });

  final String id;
  final int index;

  /// Jouable en escarmouche (le clan des Corbeaux se débloque plus tard).
  final bool playable;
  final String hero;
  final List<TechEffect> effects;
  final Stock startBonus;
  final AiPersonality personality;
}

/// Réglages de comportement de l'IA propres à un clan.
class AiPersonality {
  const AiPersonality({
    required this.aggression,
    required this.economy,
    required this.towers,
    required this.siege,
    required this.cavalry,
    required this.raidWave,
  });

  /// Pourcentages 0..100.
  final int aggression;
  final int economy;
  final int towers;
  final int siege;
  final int cavalry;

  /// Taille d'armée déclenchant une vague d'attaque.
  final int raidWave;
}

class DifficultyDef {
  const DifficultyDef({
    required this.id,
    required this.index,
    required this.thinkTicks,
    required this.gatherBonusPercent,
    required this.attackWaveScale,
    required this.maxVillagers,
    required this.useHero,
    required this.usePowers,
    required this.shownBonus,
  });

  final String id;
  final int index;
  final int thinkTicks;
  final int gatherBonusPercent;
  final int attackWaveScale;
  final int maxVillagers;
  final bool useHero;
  final bool usePowers;

  /// Le bonus doit être affiché à l'écran (difficulté Difficile).
  final bool shownBonus;
}

class AiDef {
  const AiDef({
    required this.difficulties,
    required this.watchdogTicks,
    required this.shares,
    required this.hutMargin,
    required this.defenseRadius,
    required this.retreatRatioPercent,
    required this.attackMinArmy,
  });

  final List<DifficultyDef> difficulties;
  final int watchdogTicks;

  /// Répartition cible des villageois par ressource (pourcentages).
  final Map<Res, int> shares;
  final int hutMargin;
  final int defenseRadius;
  final int retreatRatioPercent;
  final int attackMinArmy;
}

/// Réglages du combat (fichier balance).
class CombatDef {
  const CombatDef({
    required this.leashTiles,
    required this.heightBonusPercent,
    required this.collapseDamage,
    required this.maxProjectiles,
    required this.drumMax,
    required this.drumPerDamage,
    required this.drumPerKill,
    required this.stunImmunityTicks,
    required this.slowCapPercent,
    required this.attackBuffCapPercent,
    required this.attackDebuffCapPercent,
    required this.armorBuffCap,
    required this.maxEffects,
    required this.heroReviveCostPercent,
    required this.auraPeriodTicks,
    required this.acquirePeriod,
    required this.siegeBuildingArmorDivisor,
    required this.projectileTtlTicks,
    required this.straggleSeconds,
  });

  final int leashTiles;
  final int heightBonusPercent;
  final int collapseDamage;
  final int maxProjectiles;
  final int drumMax;
  final int drumPerDamage;
  final int drumPerKill;
  final int stunImmunityTicks;
  final int slowCapPercent;
  final int attackBuffCapPercent;
  final int attackDebuffCapPercent;
  final int armorBuffCap;
  final int maxEffects;
  final int heroReviveCostPercent;
  final int auraPeriodTicks;
  final int acquirePeriod;
  final int siegeBuildingArmorDivisor;
  final int projectileTtlTicks;

  /// Après ce délai sans bâtiment vital, un joueur est éliminé.
  final int straggleSeconds;
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
    required this.combat,
    required this.mapStyles,
  });

  final CombatDef combat;
  final List<MapStyleDef> mapStyles;
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

/// Style de carte : décalages appliqués aux seuils du générateur.
class MapStyleDef {
  const MapStyleDef({
    required this.id,
    required this.waterDelta,
    required this.mountainDelta,
    required this.forestDelta,
  });

  final String id;
  final int waterDelta;
  final int mountainDelta;
  final int forestDelta;
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

  /// Variante de style de carte (décalages des seuils de bruit).
  MapGenDef withStyle(MapStyleDef s) => MapGenDef(
    baseClearRadius: baseClearRadius,
    playerRingPercent: playerRingPercent,
    noiseScale: noiseScale,
    waterLevel: (waterLevel + s.waterDelta).clamp(0, 255),
    deepWaterLevel: (deepWaterLevel + s.waterDelta).clamp(0, 255),
    mountainLevel: (mountainLevel + s.mountainDelta).clamp(0, 255),
    forestThreshold: (forestThreshold + s.forestDelta).clamp(0, 255),
    treesPerStartForest: treesPerStartForest,
    startForests: startForests,
    startBerries: startBerries,
    startStone: startStone,
    startIron: startIron,
    startGold: startGold,
    startGame: startGame,
    scatterPerThousand: scatterPerThousand,
    maxAttempts: maxAttempts,
  );

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
