import 'package:age_of_empire_camer/app/app.dart';
import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/app/window/window_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container() => ProviderContainer(
  overrides: <Override>[
    closeCoordinatorProvider.overrideWithValue(
      CloseCoordinator(terminate: () async {}),
    ),
    windowServiceProvider.overrideWithValue(NoopWindowService()),
  ],
);

void main() {
  // Tailles de référence de l'Analyse §15.1, échelles 80 / 100 / 150 %.
  const sizes = <Size>[
    Size(800, 360),
    Size(915, 412),
    Size(1280, 800),
    Size(1280, 720),
    Size(1920, 1080),
    Size(2560, 1080),
  ];

  for (final size in sizes) {
    for (final scale in <double>[0.8, 1, 1.5]) {
      testWidgets(
        'menu sans débordement ${size.width}x${size.height} échelle $scale',
        (tester) async {
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final container = _container();
          addTearDown(container.dispose);
          container.read(uiScaleProvider.notifier).state = scale;
          await tester.pumpWidget(
            UncontrolledProviderScope(container: container, child: const App()),
          );
          await tester.pumpAndSettle();
          expect(find.text('Les Royaumes du Fleuve'), findsOneWidget);
          expect(find.text('Options'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('ouvre les options', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Échelle de l'interface"), findsOneWidget);
  });
}
