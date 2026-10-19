import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';

/// Textes de l'interface de jeu (français). Regroupés ici pour être migrés vers
/// des fichiers `.arb` en Phase 9 sans toucher aux widgets.
abstract final class S {
  static const Map<String, String> _units = <String, String>{
    'villager': 'Villageois',
    'spearman': 'Lancier',
    'archer': 'Archer',
    'iron_warrior': 'Guerrier de fer',
    'horseman': 'Cavalier',
    'catapult': 'Catapulte',
    'royal_guard': 'Garde royal',
    'river_guard': 'Garde du Fleuve',
    'net_thrower': 'Lanceur de filet',
    'forge_hammer': 'Marteau de forge',
    'wind_rider': 'Cavalier du vent',
    'raven': 'Corbeau',
    'hero_mbarga': 'Mbarga',
    'hero_sanaga': 'Mama Sanaga',
    'hero_ngolo': 'Ngolo',
    'hero_dikoume': 'Dikoumé',
    'hero_kaba': 'Kaba le Corbeau',
  };

  static const Map<String, String> _buildings = <String, String>{
    'town_center': 'Centre-ville',
    'hut': 'Hutte',
    'granary': 'Grenier',
    'lumber_camp': 'Camp de bûcherons',
    'mining_camp': 'Camp minier',
    'field': 'Champ',
    'barracks': 'Caserne',
    'forge': 'Forge',
    'market': 'Marché',
    'palace': 'Palais',
    'wall': 'Rempart',
    'tower': 'Tour de guet',
    'stable': 'Écurie',
    'siege_workshop': 'Atelier de siège',
    'altar': 'Autel',
    'fortress': 'Forteresse',
  };

  static const Map<String, String> _techs = <String, String>{
    'carry_1': 'Paniers renforcés',
    'gather_food_1': 'Outils de culture',
    'gather_wood_1': 'Haches de pierre polie',
    'gather_stone_1': 'Pics de carrier',
    'gather_iron_1': 'Pioches de fer',
    'gather_gold_1': 'Batées d’orpailleur',
    'melee_attack_1': 'Lames affûtées',
    'melee_attack_2': 'Lames de fer trempé',
    'pierce_attack_1': 'Flèches empennées',
    'pierce_attack_2': 'Pointes de fer',
    'armor_inf_1': 'Boucliers renforcés',
    'armor_inf_2': 'Cuirasses de cuir durci',
    'armor_cav_1': 'Caparaçons',
    'armor_archer_1': 'Gilets matelassés',
    'hp_inf_1': 'Entraînement rigoureux',
    'siege_1': 'Ingénierie de siège',
  };

  static const Map<String, String> _powers = <String, String>{
    'rally_cry': 'Cri de ralliement',
    'spear_wall': 'Mur de lances',
    'arrow_rain': 'Pluie de flèches',
    'crushing_blow': 'Frappe écrasante',
    'charge': 'Charge',
    'lion_fury': 'Fureur du lion',
    'ancestor_drum': 'Tambour des Ancêtres',
    'unity': 'Unité',
    'ancestor_aura': 'Aura des Ancêtres',
    'tide': 'Marée',
    'flood': 'Grande marée',
    'tide_aura': 'Aura de la marée',
    'war_forge': 'Forge de guerre',
    'iron_thunder': 'Tonnerre de fer',
    'forge_aura': 'Aura de la forge',
    'wind_gallop': 'Galop du vent',
    'stampede': 'Stampede',
    'wind_aura': 'Aura du vent',
    'raven_swarm': 'Nuée',
    'raven_storm': 'Tempête de corbeaux',
    'raven_aura': 'Aura des corbeaux',
    'lightning': 'Foudre',
    'heal_spell': 'Soin',
    'rage': 'Rage',
    'freeze': 'Gel',
  };

  static const Map<String, String> _powerDescriptions = <String, String>{
    'rally_cry': '+25 % de vitesse de récolte aux alentours pendant 10 s.',
    'spear_wall': 'Armure +3 et attaque +25 % pendant 4 s, mais immobile.',
    'arrow_rain': 'Zone : 7 dégâts par seconde pendant 3 s aux ennemis.',
    'crushing_blow': 'Étourdit la cible 2 s et inflige 10 dégâts.',
    'charge': 'Premier coup doublé, vitesse +50 % pendant 3 s.',
    'lion_fury': '+50 % de dégâts, immunité aux étourdissements 6 s.',
    'ancestor_drum': 'Alliés proches : +20 % dégâts et vitesse pendant 15 s.',
    'unity': 'Soigne les alliés de 80 PV et purge les effets négatifs.',
    'ancestor_aura': 'Alliés proches : +5 % de dégâts en permanence.',
    'tide': 'Ralentit les ennemis de la zone de 40 % pendant 8 s.',
    'flood': 'Zone : 30 dégâts et ralentissement de 50 %.',
    'tide_aura': 'Alliés proches : armure +1.',
    'war_forge': 'Alliés proches : +25 % de dégâts pendant 12 s.',
    'iron_thunder': 'Zone : 60 dégâts et courte paralysie.',
    'forge_aura': 'Alliés proches : armure +1.',
    'wind_gallop': 'Alliés proches : vitesse +60 % pendant 5 s.',
    'stampede': 'Étourdit et blesse les ennemis autour du héros.',
    'wind_aura': 'Alliés proches : vitesse +8 %.',
    'raven_swarm': 'Zone : les ennemis aveuglés perdent 60 % de dégâts 10 s.',
    'raven_storm': 'Zone : 40 dégâts et ralentissement.',
    'raven_aura': 'Alliés proches : +5 % de dégâts.',
    'lightning': 'Foudroie les ennemis de la zone (50 dégâts).',
    'heal_spell': 'Soigne les alliés de la zone (60 PV).',
    'rage': 'Alliés de la zone : +40 % dégâts, +30 % vitesse, 10 s.',
    'freeze': 'Gèle les ennemis de la zone 4 s.',
  };

  static const Map<String, String> _clans = <String, String>{
    'fleuve': 'Clan du Fleuve',
    'pecheurs': 'Clan des Pêcheurs',
    'forgerons': 'Clan des Forgerons',
    'cavaliers': 'Clan des Cavaliers',
    'corbeaux': 'Clan des Corbeaux',
  };

  static const Map<String, String> _clanDescriptions = <String, String>{
    'fleuve': 'Équilibré. Infanterie +10 % de dégâts. Héros : Mbarga.',
    'pecheurs':
        'Économie. Nourriture +20 %, bois +10 %, archers +1 de portée. '
        'Héroïne : Mama Sanaga.',
    'forgerons':
        'Sièges et défenses. Fer +15 %, sièges +20 %, bâtiments renforcés. '
        'Héros : Ngolo.',
    'cavaliers':
        'Raids rapides. Cavalerie plus rapide, plus solide et plus forte. '
        'Héros : Dikoumé.',
    'corbeaux': 'Agressifs. Toute l’armée +10 % de dégâts. Héros : Kaba.',
  };

  static const Map<String, String> _resources = <String, String>{
    'tree': 'Arbre',
    'berries': 'Buisson de baies',
    'game': 'Gibier',
    'quarry': 'Carrière',
    'iron_mine': 'Mine de fer',
    'gold_mine': 'Mine d’or',
  };

  static const List<String> _ages = <String>[
    'Âge des Villages',
    'Âge des Royaumes',
    'Âge des Empires',
    'Âge d’Or',
  ];

  static String power(String id) => _powers[id] ?? id;
  static String powerDescription(String id) => _powerDescriptions[id] ?? '';
  static String clan(String id) => _clans[id] ?? id;
  static String clanDescription(String id) => _clanDescriptions[id] ?? '';
  static const List<String> difficulties = <String>[
    'Facile',
    'Normal',
    'Difficile',
  ];
  static const List<String> mapStyles = <String>[
    'Plaines',
    'Forêts',
    'Savane',
    'Hauts plateaux',
    'Fleuves',
  ];
  static String unit(String id) => _units[id] ?? id;
  static String building(String id) => _buildings[id] ?? id;
  static String tech(String id) => _techs[id] ?? id;
  static String resourceNode(String id) => _resources[id] ?? id;
  static String age(int i) => _ages[i.clamp(0, _ages.length - 1)];

  static String res(Res r) => switch (r) {
    Res.food => 'Nourriture',
    Res.wood => 'Bois',
    Res.stone => 'Pierre',
    Res.iron => 'Fer',
    Res.gold => 'Or',
  };

  static String stance(Stance s) => switch (s) {
    Stance.aggressive => 'Agressif',
    Stance.defensive => 'Défensif',
    Stance.passive => 'Passif',
    Stance.follow => 'Suivre',
  };

  static String unitState(Unit u) => switch (u.state) {
    UnitState.idle => 'Inactif',
    UnitState.moving => 'En déplacement',
    UnitState.gathering =>
      u.phase == Phase.returning ? 'Dépose sa charge' : 'Récolte',
    UnitState.building => 'Construit',
    UnitState.attacking => 'Attaque',
    UnitState.garrisoned => 'En garnison',
    UnitState.dead => 'Mort',
  };

  /// Message lisible pour un refus de commande (`CmdResult.name`).
  static String rejection(String name) => switch (name) {
    'cannotAfford' => 'Ressources insuffisantes',
    'popCapped' => 'Population maximale atteinte',
    'queueFull' => 'File de production pleine',
    'locked' => 'Pas encore débloqué',
    'badPlacement' => 'Emplacement impossible',
    'unexplored' => 'Zone inexplorée',
    'notComplete' => 'Bâtiment inachevé',
    'noUnits' => 'Aucune unité utilisable',
    'wrongTarget' => 'Cible invalide',
    'nothingToDo' => 'Pas disponible (recharge, déjà en cours…)',
    'outOfRange' => 'Hors de portée',
    _ => 'Action impossible',
  };

  static const String pause = 'Pause';
  static const String resume = 'Reprendre';
  static const String menu = 'Menu';
  static const String save = 'Sauvegarder';
  static const String quitToMenu = 'Quitter vers le menu';
  static const String idleVillagers = 'Villageois inactifs';
  static const String build = 'Construire';
  static const String stop = 'Arrêt';
  static const String deleteBuilding = 'Supprimer';
  static const String confirmDeleteTitle = 'Supprimer ce bâtiment ?';
  static const String confirm = 'Confirmer';
  static const String cancel = 'Annuler';
  static const String multiSelect = 'Sélection multiple';
  static const String queue = 'File d’ordres';
  static const String reseed = 'Replanter';
  static const String ungarrison = 'Faire sortir';
  static const String market = 'Marché';
  static const String ageUp = 'Âge suivant';
  static const String resign = 'Abandonner';
  static const String victory = 'Victoire !';
  static const String defeat = 'Défaite';
  static const String draw = 'Égalité';
  static const String spectator = 'Spectateur';
  static const String powers = 'Pouvoirs';
  static const String drum = 'Énergie du tambour';
}
