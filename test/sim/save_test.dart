import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:age_of_empire_camer/meta/save_store.dart';
import 'package:age_of_empire_camer/sim/core/hashing.dart';
import 'package:age_of_empire_camer/sim/core/rng.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/save/save_codec.dart';
import 'package:age_of_empire_camer/sim/testing/command_fuzzer.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

/// Partie bien avancée : files de production, récolte, flow fields, combats.
World _busyGame(int seed, int ticks) {
  final w = createGame(testDefs, seed: seed, size: 48, players: 3);
  final fuzz = CommandFuzzer(seed + 1000);
  for (var t = 0; t < ticks; t++) {
    if (t % 3 == 0) w.submit(fuzz.next(w));
    w.step();
  }
  return w;
}

Uint8List _flip(Uint8List b, int i) => Uint8List.fromList(b)..[i] ^= 0x40;

SaveError? _errOf(Uint8List b) {
  try {
    SaveCodec.decode(testDefs, b);
    return null;
  } on SaveException catch (e) {
    return e.error;
  }
}

Uint8List _craft(String payload) {
  final p = utf8.encode(payload);
  final out = Uint8List(SaveCodec.headerSize + p.length)
    ..setRange(0, 4, SaveCodec.magic);
  ByteData.sublistView(out)
    ..setUint16(4, SaveCodec.formatVersion)
    ..setUint32(8, p.length)
    ..setUint32(12, Crc32.compute(p));
  out.setRange(SaveCodec.headerSize, out.length, p);
  return out;
}

void main() {
  test('charger(sauvegarder(état)) == état (JSON structurel et hash)', () {
    for (final seed in [1, 2, 3, 4]) {
      final w = _busyGame(seed, 900);
      final back = SaveCodec.decode(testDefs, SaveCodec.encode(w));
      expect(
        jsonEncode(back.toJson()),
        jsonEncode(w.toJson()),
        reason: 'graine $seed',
      );
      expect(back.stateHash(), w.stateHash());
      expect(back.tick, w.tick);
    }
  });

  test('charger puis continuer == continuer sans interruption', () {
    for (final seed in [5, 6, 7]) {
      final a = _busyGame(seed, 700);
      final b = SaveCodec.decode(testDefs, SaveCodec.encode(a));
      final fuzzA = CommandFuzzer(seed * 31);
      final fuzzB = CommandFuzzer(seed * 31);
      for (var t = 0; t < 1200; t++) {
        if (t % 4 == 0) {
          a.submit(fuzzA.next(a));
          b.submit(fuzzB.next(b));
        }
        a.step();
        b.step();
        if (t % 50 == 0) {
          expect(
            b.stateHash(),
            a.stateHash(),
            reason: 'graine $seed tick ${a.tick}',
          );
        }
      }
      expect(b.stateHash(), a.stateHash());
    }
  });

  test('en-têtes : magie, version trop récente, troncature, CRC', () {
    final bytes = SaveCodec.encode(_busyGame(2, 100));
    expect(_errOf(bytes), isNull);
    expect(_errOf(_flip(bytes, 0)), SaveError.badMagic);
    expect(_errOf(_flip(bytes, SaveCodec.headerSize + 10)), SaveError.corrupt);
    expect(_errOf(Uint8List.sublistView(bytes, 0, 10)), SaveError.truncated);
    expect(
      _errOf(Uint8List.sublistView(bytes, 0, bytes.length - 5)),
      SaveError.truncated,
    );
    final newer = Uint8List.fromList(bytes);
    ByteData.sublistView(newer).setUint16(4, SaveCodec.formatVersion + 1);
    expect(_errOf(newer), SaveError.tooNew);
    final huge = Uint8List.fromList(bytes);
    ByteData.sublistView(huge).setUint32(8, SaveCodec.maxPayload + 1);
    expect(_errOf(huge), SaveError.tooLarge);
  });

  test('charge utile non JSON ou structure fausse ⇒ SaveException', () {
    for (final payload in [
      'pas du json',
      '[1,2,3]',
      '{}',
      '{"format":1}',
      '{"format":9}',
    ]) {
      expect(
        () => SaveCodec.decode(testDefs, _craft(payload)),
        throwsA(isA<SaveException>()),
        reason: payload,
      );
    }
  });

  test('migration manquante pour une ancienne version : refus clair', () {
    final bytes = SaveCodec.encode(_busyGame(2, 50));
    final old = Uint8List.fromList(bytes);
    ByteData.sublistView(old).setUint16(4, 0);
    expect(_errOf(old), SaveError.invalid);
  });

  test('sauvegarde au CRC valide mais incohérente : refusée proprement', () {
    final w = _busyGame(4, 300);
    Map<String, dynamic> base() =>
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>;
    List<dynamic> list(Map<String, dynamic> j, String k) =>
        j[k] as List<dynamic>;
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'chemin hors carte': (j) {
        final u = list(j, 'units').first as Map<String, dynamic>;
        u['path'] = <int>[999999];
        u['pathIdx'] = 0;
      },
      'bâtiment hors carte': (j) {
        (list(j, 'buildings').first as Map<String, dynamic>)['tx'] = 9999;
      },
      'propriétaire invalide': (j) {
        (list(j, 'units').first as Map<String, dynamic>)['owner'] = 42;
      },
      'terrain inconnu': (j) {
        final map = j['map'] as Map<String, dynamic>;
        final bytes = base64Decode(map['terrain'] as String);
        bytes[3] = 200;
        map['terrain'] = base64Encode(bytes);
      },
      'tableau de carte tronqué': (j) {
        (j['map'] as Map<String, dynamic>)['terrain'] = base64Encode(<int>[
          1,
          2,
          3,
        ]);
      },
      'taille de carte absurde': (j) {
        (j['map'] as Map<String, dynamic>)['w'] = 100000;
      },
      'ressource négative': (j) {
        (list(j, 'players').first as Map<String, dynamic>)['stock'] = <int>[
          -5,
          0,
          0,
          0,
          0,
        ];
      },
      'ordre vers une entité inexistante': (j) {
        final u = list(j, 'units').first as Map<String, dynamic>;
        u['orders'] = <dynamic>[
          <int>[1, 987654, 0],
        ];
        u['state'] = 1;
      },
      'type de charge invalide': (j) {
        (list(j, 'units').first as Map<String, dynamic>)['carryRes'] = 77;
      },
      'définition d’unité inexistante': (j) {
        (list(j, 'units').first as Map<String, dynamic>)['def'] = 500;
      },
      'file de production invalide': (j) {
        final b =
            list(j, 'buildings').firstWhere(
                  (e) => (e as Map<String, dynamic>)['complete'] == true,
                )
                as Map<String, dynamic>;
        b['queue'] = <dynamic>[
          <String, dynamic>{
            't': false,
            'd': 999,
            'r': 5,
            'p': <int>[0, 0, 0, 0, 0],
          },
        ];
      },
    };
    for (final e in mutations.entries) {
      final j = base();
      e.value(j);
      expect(
        () => SaveCodec.decode(testDefs, _craft(jsonEncode(j))),
        throwsA(isA<SaveException>()),
        reason: e.key,
      );
    }
    // Et la sauvegarde non modifiée reste acceptée.
    expect(
      SaveCodec.decode(testDefs, _craft(jsonEncode(base()))).stateHash(),
      w.stateHash(),
    );
  });

  test('octets aléatoires et corruptions : seulement des SaveException', () {
    final bytes = SaveCodec.encode(_busyGame(3, 200));
    final r = Rng(5);
    for (var i = 0; i < 200; i++) {
      final b = Uint8List.fromList(bytes);
      final n = r.range(1, 6);
      for (var k = 0; k < n; k++) {
        b[r.nextInt(b.length)] = r.nextInt(256);
      }
      try {
        SaveCodec.decode(testDefs, b);
      } on SaveException {
        // attendu : aucune autre exception ne doit s'échapper
      }
    }
    for (var i = 0; i < 100; i++) {
      final b = Uint8List.fromList(<int>[
        for (var k = 0; k < r.range(0, 60); k++) r.nextInt(256),
      ]);
      expect(
        () => SaveCodec.decode(testDefs, b),
        throwsA(isA<SaveException>()),
      );
    }
  });

  group('SaveStore', () {
    late Directory dir;
    late SaveStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('rdf_save');
      store = SaveStore(dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('écriture atomique, relecture, slots', () async {
      final w = _busyGame(1, 150);
      expect(store.exists('slot1'), isFalse);
      await store.saveWorld('slot1', w);
      expect(store.exists('slot1'), isTrue);
      expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
      final back = await store.loadWorld(testDefs, 'slot1');
      expect(back!.stateHash(), w.stateHash());
      expect(store.slots(), ['slot1']);
      await store.delete('slot1');
      expect(store.slots(), isEmpty);
      expect(await store.loadWorld(testDefs, 'slot1'), isNull);
    });

    test('sauvegarde principale corrompue : bascule sur .bak', () async {
      final w1 = _busyGame(1, 120);
      final w2 = _busyGame(1, 240);
      await store.saveWorld('s', w1);
      await store.saveWorld('s', w2);
      final sav = File('${dir.path}/s.sav');
      final bytes = sav.readAsBytesSync();
      sav.writeAsBytesSync(_flip(bytes, bytes.length ~/ 2));
      final back = await store.loadWorld(testDefs, 's');
      expect(back, isNotNull);
      expect(back!.tick, w1.tick, reason: 'ancienne sauvegarde intacte');
      File('${dir.path}/s.bak').writeAsBytesSync([1, 2, 3]);
      expect(await store.loadWorld(testDefs, 's'), isNull);
    });

    test('écriture interrompue (.tmp résiduel) : sauvegarde valide', () async {
      final w = _busyGame(2, 100);
      await store.saveWorld('s', w);
      File('${dir.path}/s.tmp').writeAsBytesSync([9, 9, 9]);
      final back = await store.loadWorld(testDefs, 's');
      expect(back!.stateHash(), w.stateHash());
      await store.saveWorld('s', w);
      expect(File('${dir.path}/s.tmp').existsSync(), isFalse);
    });

    test('noms d’emplacement dangereux refusés', () async {
      final w = _busyGame(2, 50);
      for (final bad in ['../x', 'a/b', '', 'a b', 'x' * 60, r'c:\x']) {
        expect(() => store.exists(bad), throwsArgumentError, reason: bad);
        await expectLater(store.saveWorld(bad, w), throwsArgumentError);
      }
    });

    test('autosauvegarde tournante : remplace la plus ancienne', () async {
      final w = _busyGame(3, 60);
      final used = <String>[];
      for (var i = 0; i < 5; i++) {
        used.add(await store.writeRotating('auto', 3, w));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(used.sublist(0, 3).toSet().length, 3);
      expect(used[3], used[0]);
      expect(store.slots().length, 3);
    });
  });
}
