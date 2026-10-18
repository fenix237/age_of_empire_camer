import 'dart:convert';
import 'dart:io';

import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

Map<String, String> _files() => <String, String>{
  for (final n in Defs.fileNames)
    n: File('assets/data/$n.json').readAsStringSync(),
};

/// Modifie un fichier JSON via [edit] puis tente de charger.
Defs _load(String file, void Function(Map<String, dynamic>) edit) {
  final files = _files();
  final j = jsonDecode(files[file]!) as Map<String, dynamic>;
  edit(j);
  files[file] = jsonEncode(j);
  return Defs.fromFiles(files);
}

Map<String, dynamic> _unit0(Map<String, dynamic> j) =>
    (j['units'] as List<dynamic>)[0] as Map<String, dynamic>;

void main() {
  test('les données réelles se chargent', () {
    expect(testDefs.units, isNotEmpty);
    expect(testDefs.unit('villager').villager, isTrue);
    expect(testDefs.building('town_center').townCenter, isTrue);
    expect(testDefs.building('field').isField, isTrue);
    expect(testDefs.tech('carry_1').effects.first.stat, 'carry');
    expect(testDefs.unit('villager').speedFxPerTick, 25);
    expect(testDefs.tryUnit('nope'), isNull);
    expect(testDefs.tryBuilding('nope'), isNull);
    expect(testDefs.tryTech('nope'), isNull);
    expect(testDefs.resource('tree').res, Res.wood);
    expect(testDefs.ages.length, 4);
    expect(testDefs.balance.maxPopulation, 200);
  });

  test('chaque unité entraînée/recherche référencée existe', () {
    for (final b in testDefs.buildings) {
      for (final u in b.trains) {
        expect(testDefs.tryUnit(u), isNotNull, reason: u);
      }
      for (final t in b.researches) {
        expect(testDefs.tryTech(t), isNotNull, reason: t);
      }
    }
  });

  test('erreur claire : fichier manquant', () {
    final files = _files()..remove('units');
    expect(
      () => Defs.fromFiles(files),
      throwsA(isA<DataException>().having((e) => e.file, 'file', 'units')),
    );
  });

  test('erreur claire : JSON illisible', () {
    final files = _files()..['units'] = '{ pas du json';
    expect(() => Defs.fromFiles(files), throwsA(isA<DataException>()));
  });

  test('erreur claire : racine non objet', () {
    final files = _files()..['units'] = '[1,2]';
    expect(() => Defs.fromFiles(files), throwsA(isA<DataException>()));
  });

  test('valeur hors bornes signalée avec chemin', () {
    expect(
      () => _load('units', (j) {
        _unit0(j)['hp'] = -5;
      }),
      throwsA(
        isA<DataException>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('units'), contains('hp'), contains(r'$.units[0]')),
        ),
      ),
    );
  });

  test('type invalide', () {
    expect(
      () => _load('units', (j) {
        _unit0(j)['hp'] = 'beaucoup';
      }),
      throwsA(isA<DataException>()),
    );
  });

  test('identifiants en double refusés', () {
    expect(
      () => _load('units', (j) {
        final l = j['units'] as List<dynamic>;
        l.add(Map<String, dynamic>.of(l.first as Map<String, dynamic>));
      }),
      throwsA(isA<DataException>()),
    );
  });

  test('référence inconnue refusée (unité entraînée)', () {
    expect(
      () => _load('buildings', (j) {
        ((j['buildings'] as List<dynamic>)[0]
            as Map<String, dynamic>)['trains'] = [
          'dragon',
        ];
      }),
      throwsA(isA<DataException>()),
    );
  });

  test('ressource inconnue dans un coût', () {
    expect(
      () => _load('units', (j) {
        ((j['units'] as List<dynamic>)[0] as Map<String, dynamic>)['cost'] = {
          'mithril': 5,
        };
      }),
      throwsA(isA<DataException>()),
    );
  });

  test('villageois sans capacité de portage refusé', () {
    expect(
      () => _load('units', (j) {
        ((j['units'] as List<dynamic>)[0]
                as Map<String, dynamic>)['carryCapacity'] =
            0;
      }),
      throwsA(isA<DataException>()),
    );
  });

  test('taille de bâtiment invalide', () {
    expect(
      () => _load('buildings', (j) {
        ((j['buildings'] as List<dynamic>)[0]
            as Map<String, dynamic>)['size'] = [
          0,
          3,
        ];
      }),
      throwsA(isA<DataException>()),
    );
  });

  test('coût de terrain inférieur à 10 refusé (heuristique A*)', () {
    expect(
      () => _load('terrain', (j) {
        ((j['terrain'] as List<dynamic>)[0]
                as Map<String, dynamic>)['moveCost'] =
            5;
      }),
      throwsA(isA<DataException>()),
    );
  });

  test('effet de recherche inconnu refusé', () {
    expect(
      () => _load('techs', (j) {
        final t0 = (j['techs'] as List<dynamic>)[0] as Map<String, dynamic>;
        final e0 = (t0['effects'] as List<dynamic>)[0] as Map<String, dynamic>;
        e0['stat'] = 'magie';
      }),
      throwsA(isA<DataException>()),
    );
  });

  test('stock : opérations', () {
    final a = Stock.of([10, 20, 0, 0, 5]);
    final b = Stock.fromMap({Res.food: 4, Res.gold: 5});
    expect(a.covers(b), isTrue);
    a.subtract(b);
    expect(a.v, [6, 20, 0, 0, 0]);
    expect(a.covers(b), isFalse);
    a.add(b);
    expect(a.v, [10, 20, 0, 0, 5]);
    expect(a.scaled(1, 2).v, [5, 10, 0, 0, 2]);
    expect(Stock.fromJson(a.toJson()), a);
    expect(a.copy(), a);
    expect(a.hashCode, a.copy().hashCode);
    expect(Stock().isZero, isTrue);
    expect(a.toString(), contains('Stock'));
    a[Res.wood] = 1;
    expect(a[Res.wood], 1);
    expect(Res.tryParse('wood'), Res.wood);
    expect(Res.tryParse('x'), isNull);
  });
}
