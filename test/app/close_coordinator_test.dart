import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGuard implements CloseGuard {
  _FakeGuard({
    this.unsaved = true,
    this.decision = CloseDecision.saveAndQuit,
    this.saveOk = true,
    this.saveThrows = false,
  });

  bool unsaved;
  CloseDecision decision;
  bool saveOk;
  bool saveThrows;
  int saves = 0;
  int asks = 0;

  @override
  bool get hasUnsavedChanges => unsaved;

  @override
  Future<CloseDecision> askUser() async {
    asks++;
    return decision;
  }

  @override
  Future<bool> save() async {
    saves++;
    if (saveThrows) throw StateError('disque plein');
    return saveOk;
  }
}

void main() {
  late int terminated;
  late CloseCoordinator coordinator;

  setUp(() {
    terminated = 0;
    coordinator = CloseCoordinator(terminate: () async => terminated++);
  });

  test('ferme immédiatement sans garde', () async {
    expect(await coordinator.requestClose(), isTrue);
    expect(terminated, 1);
  });

  test("ferme sans question s'il n'y a rien à sauvegarder", () async {
    final guard = _FakeGuard(unsaved: false);
    coordinator.setGuard(guard);
    expect(await coordinator.requestClose(), isTrue);
    expect(guard.asks, 0);
    expect(terminated, 1);
  });

  test('sauvegarde puis quitte', () async {
    final guard = _FakeGuard();
    coordinator.setGuard(guard);
    expect(await coordinator.requestClose(), isTrue);
    expect(guard.saves, 1);
    expect(terminated, 1);
  });

  test("annuler garde l'application ouverte", () async {
    final guard = _FakeGuard(decision: CloseDecision.cancel);
    coordinator.setGuard(guard);
    expect(await coordinator.requestClose(), isFalse);
    expect(terminated, 0);
    // On peut redemander ensuite.
    guard.decision = CloseDecision.quitWithoutSaving;
    expect(await coordinator.requestClose(), isTrue);
    expect(guard.saves, 0);
  });

  test(
    'échec de sauvegarde = pas de fermeture (aucune perte de données)',
    () async {
      final guard = _FakeGuard(saveOk: false);
      coordinator.setGuard(guard);
      expect(await coordinator.requestClose(), isFalse);
      expect(terminated, 0);
    },
  );

  test('exception pendant la sauvegarde = pas de fermeture', () async {
    final guard = _FakeGuard(saveThrows: true);
    coordinator.setGuard(guard);
    expect(await coordinator.requestClose(), isFalse);
    expect(terminated, 0);
  });

  test('arrêt forcé : sauvegarde sans dialogue puis ferme', () async {
    final guard = _FakeGuard();
    coordinator.setGuard(guard);
    expect(await coordinator.requestClose(force: true), isTrue);
    expect(guard.asks, 0);
    expect(guard.saves, 1);
    expect(terminated, 1);
  });

  test('nettoyages en ordre inverse, une erreur ne bloque pas', () async {
    final order = <int>[];
    coordinator
      ..addDisposer(() async => order.add(1))
      ..addDisposer(() async => throw StateError('boom'))
      ..addDisposer(() async => order.add(3));
    expect(await coordinator.requestClose(), isTrue);
    expect(order, <int>[3, 1]);
  });

  test('deux demandes simultanées : une seule fermeture', () async {
    final results = await Future.wait(<Future<bool>>[
      coordinator.requestClose(),
      coordinator.requestClose(),
    ]);
    expect(results.where((r) => r).length, 1);
    expect(terminated, 1);
  });
}
