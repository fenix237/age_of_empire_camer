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
  };

  static const Map<String, String> _techs = <String, String>{
    'carry_1': 'Paniers renforcés',
    'gather_food_1': 'Outils de culture',
    'gather_wood_1': 'Haches de pierre polie',
    'gather_stone_1': 'Pics de carrier',
    'gather_iron_1': 'Pioches de fer',
    'gather_gold_1': 'Batées d’orpailleur',
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
    'nothingToDo' => 'Rien à faire',
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
}
