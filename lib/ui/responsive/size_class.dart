import 'package:flutter/widgets.dart';

/// Classe de taille d'écran (largeur logique en dp) — Analyse §15.1.
enum SizeClass {
  /// Téléphone (< 700 dp).
  compact,

  /// Tablette ou petite fenêtre (700–1100 dp).
  medium,

  /// PC (> 1100 dp).
  large
  ;

  static const double compactMax = 700;
  static const double mediumMax = 1100;

  static SizeClass fromWidth(double width) {
    if (width < compactMax) return SizeClass.compact;
    if (width <= mediumMax) return SizeClass.medium;
    return SizeClass.large;
  }

  /// Taille minimale d'une cible tactile (dp) dans cette classe.
  double get minTouchTarget => this == SizeClass.large ? 36 : 48;
}

/// Échelle d'interface autorisée (80–150 %).
const double kMinUiScale = 0.8;
const double kMaxUiScale = 1.5;

double clampUiScale(double value) =>
    value.isNaN ? 1 : value.clamp(kMinUiScale, kMaxUiScale);

/// Construit selon la classe de taille de l'espace disponible.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, SizeClass sizeClass) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return builder(context, SizeClass.fromWidth(width));
      },
    );
  }
}
