import 'package:age_of_empire_camer/sim/pathfinding/astar.dart';
import 'package:age_of_empire_camer/sim/pathfinding/flow_field.dart';
import 'package:age_of_empire_camer/sim/world/game_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

GameMap _grass(int w, int h) => GameMap(w, h, testDefs.terrain);

/// Pose un mur d'occupation (obstacle) sur une ligne ou colonne.
void _wall(GameMap m, int x0, int y0, int x1, int y1) {
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      m.occupant[m.index(x, y)] = 99;
    }
  }
  m.version++;
}

void main() {
  test('chemin droit sur terrain libre', () {
    final m = _grass(20, 20);
    final r = AStar(m).find(1, 1, GoalRect.tile(10, 1));
    expect(r.reached, isTrue);
    expect(r.tiles.length, 9);
    expect(r.tiles.last, m.index(10, 1));
    expect(r.tiles.first, m.index(2, 1));
  });

  test('départ dans la zone d’arrivée : chemin vide, atteint', () {
    final m = _grass(10, 10);
    final r = AStar(m).find(3, 3, GoalRect.tile(4, 4, reach: 1));
    expect(r.reached, isTrue);
    expect(r.tiles, isEmpty);
  });

  test('contourne un mur', () {
    final m = _grass(20, 20);
    _wall(m, 5, 0, 5, 14);
    final r = AStar(m).find(2, 5, GoalRect.tile(8, 5));
    expect(r.reached, isTrue);
    for (final t in r.tiles) {
      expect(m.blocked(t), isFalse);
    }
    expect(r.tiles.length, greaterThan(6));
  });

  test('pas de coupe de coin entre deux obstacles diagonaux', () {
    final m = _grass(10, 10);
    _wall(m, 4, 5, 4, 5);
    _wall(m, 5, 4, 5, 4);
    final r = AStar(m).find(4, 4, GoalRect.tile(5, 5));
    expect(r.reached, isTrue);
    expect(r.tiles.length, greaterThan(1));
  });

  test('cible inaccessible : chemin partiel vers la case la plus proche', () {
    final m = _grass(20, 20);
    _wall(m, 10, 0, 10, 19);
    final r = AStar(m).find(2, 10, GoalRect.tile(15, 10));
    expect(r.reached, isFalse);
    expect(r.tiles, isNotEmpty);
    final last = r.tiles.last;
    expect(m.xOf(last), 9);
  });

  test('cible entourée (bâtiment) : atteinte par une case adjacente', () {
    final m = _grass(20, 20);
    // Bâtiment 3x3 en (8..10, 8..10)
    _wall(m, 8, 8, 10, 10);
    final r = AStar(m).find(2, 2, const GoalRect(8, 8, 10, 10, reach: 1));
    expect(r.reached, isTrue);
    final last = r.tiles.last;
    final x = m.xOf(last);
    final y = m.yOf(last);
    expect(x >= 7 && x <= 11 && y >= 7 && y <= 11, isTrue);
    expect(m.blocked(last), isFalse);
  });

  test('île : aucune route, chemin vide non atteint', () {
    final m = _grass(20, 20);
    _wall(m, 9, 9, 11, 9);
    _wall(m, 9, 11, 11, 11);
    _wall(m, 9, 10, 9, 10);
    _wall(m, 11, 10, 11, 10);
    final r = AStar(m).find(1, 1, GoalRect.tile(10, 10));
    expect(r.reached, isFalse);
    expect(r.tiles, isNotEmpty); // se rapproche autant que possible
  });

  test('déterminisme : deux recherches identiques donnent le même chemin', () {
    final m = _grass(40, 40);
    _wall(m, 10, 5, 10, 30);
    _wall(m, 20, 10, 20, 38);
    final a = AStar(m).find(2, 20, GoalRect.tile(35, 20));
    final b = AStar(m).find(2, 20, GoalRect.tile(35, 20));
    expect(a.tiles, b.tiles);
  });

  test('limite de nœuds : renvoie le meilleur chemin partiel', () {
    final m = _grass(100, 100);
    final r = AStar(m).find(0, 0, GoalRect.tile(99, 99), nodeLimit: 50);
    expect(r.reached, isFalse);
    expect(r.tiles, isNotEmpty);
  });

  test('flow field : gradient vers l’objectif et contournement', () {
    final m = _grass(30, 30);
    _wall(m, 15, 0, 15, 20);
    final f = FlowField(1, GoalRect.tile(25, 5));
    expect(f.distance(m, m.index(25, 5)), 0);
    expect(f.distance(m, m.index(5, 5)), greaterThan(200));
    // En suivant le flow depuis (5,5) on atteint l'objectif.
    var cur = m.index(5, 5);
    for (var i = 0; i < 200 && cur != m.index(25, 5); i++) {
      final n = f.next(m, cur);
      expect(n, isNonNegative, reason: 'bloqué en ${m.xOf(cur)},${m.yOf(cur)}');
      cur = n;
    }
    expect(cur, m.index(25, 5));
  });

  test('flow field : recalcul quand la carte change', () {
    final m = _grass(20, 20);
    final f = FlowField(1, GoalRect.tile(18, 10));
    final before = f.distance(m, m.index(2, 10));
    _wall(m, 10, 0, 10, 18);
    final after = f.distance(m, m.index(2, 10));
    expect(after, greaterThan(before));
    f.drop();
    expect(f.distance(m, m.index(2, 10)), after);
  });

  test('flow field : zone isolée = inaccessible', () {
    final m = _grass(20, 20);
    _wall(m, 10, 0, 10, 19);
    final f = FlowField(1, GoalRect.tile(18, 10));
    expect(f.distance(m, m.index(2, 2)), FlowField.unreachable);
    expect(f.next(m, m.index(2, 2)), -1);
  });

  test(
    'flow field : objectif bloqué, la zone d’arrivée élargie sert de source',
    () {
      final m = _grass(20, 20);
      _wall(m, 10, 10, 10, 10);
      final f = FlowField(1, GoalRect.tile(10, 10, reach: 1));
      expect(f.distance(m, m.index(9, 10)), 0);
      expect(f.distance(m, m.index(10, 10)), FlowField.unreachable);
    },
  );
}
