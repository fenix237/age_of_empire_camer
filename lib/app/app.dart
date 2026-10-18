import 'dart:io';

import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/ui/menu/main_menu_screen.dart';
import 'package:age_of_empire_camer/ui/responsive/size_class.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = clampUiScale(ref.watch(uiScaleProvider));
    return MaterialApp(
      title: 'Les Royaumes du Fleuve',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5A2B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        // Échelle d'interface globale, sans toucher à la taille de la fenêtre.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: _DesktopShortcuts(child: child ?? const SizedBox.shrink()),
        );
      },
      home: const MainMenuScreen(),
    );
  }
}

/// F11 et Alt+Entrée : bascule plein écran (Windows). Échap ne la quitte pas.
class _DesktopShortcuts extends ConsumerWidget {
  const _DesktopShortcuts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isWindows) return child;
    void toggle() => ref.read(windowServiceProvider).toggleFullScreen();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f11): toggle,
        const SingleActivator(LogicalKeyboardKey.enter, alt: true): toggle,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
