import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/selection.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/ui/game/game_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

Future<GameController> _pump(WidgetTester tester) async {
  final w = createGame(testDefs, seed: 7);
  final c = GameController(world: w, defs: testDefs);
  tester.view.devicePixelRatio = 1.5;
  tester.view.physicalSize = const Size(1920, 1080);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        closeCoordinatorProvider.overrideWithValue(
          CloseCoordinator(terminate: () async {}),
        ),
      ],
      child: MaterialApp(home: GameScreen(controller: c)),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return c;
}

Future<void> _tap(
  WidgetTester tester,
  Offset p,
  PointerDeviceKind kind, {
  bool right = false,
}) async {
  final g = await tester.startGesture(
    p,
    kind: kind,
    buttons: right ? kSecondaryMouseButton : kPrimaryButton,
  );
  await g.up();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('souris : clic gauche sélectionne, clic droit déplace', (
    tester,
  ) async {
    final c = await _pump(tester);
    final u = c.world.unitsOf(0).first;
    final p = unitScreenPos(c.camera, u);
    await _tap(tester, p, PointerDeviceKind.mouse);
    expect(c.selection.units, <int>[u.id]);
    final tx = u.tileX;
    await _tap(
      tester,
      p + const Offset(150, 90),
      PointerDeviceKind.mouse,
      right: true,
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(u.tileX, isNot(tx));
  });

  testWidgets(
    'tactile : un appui sur le sol contre le centre-ville déplace, '
    'ne met pas en garnison',
    (tester) async {
      final c = await _pump(tester);
      final w = c.world;
      final tc = w.buildings.values.firstWhere((b) => b.owner == 0);
      final u = w.unitsOf(0).first;
      await _tap(tester, unitScreenPos(c.camera, u), PointerDeviceKind.touch);
      expect(c.selection.units, <int>[u.id]);
      // Case libre collée au flanc du centre-ville.
      final gx = tc.tx - 1;
      final gy = tc.ty + tc.def.height ~/ 2;
      final screen = c.camera.worldToScreen(Iso.tileCenter(gx, gy));
      await _tap(tester, screen, PointerDeviceKind.touch);
      expect(c.selection.units, <int>[u.id], reason: 'sélection conservée');
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(u.state, isNot(UnitState.garrisoned));
      expect(u.alive, isTrue);
    },
  );
}
