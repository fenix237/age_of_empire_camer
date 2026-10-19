import 'dart:async';
import 'dart:io';

import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/ui/campaign/campaign_screen.dart';
import 'package:age_of_empire_camer/ui/menu/new_game.dart';
import 'package:age_of_empire_camer/ui/responsive/size_class.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Menu principal (squelette de la Phase 0).
class MainMenuScreen extends ConsumerStatefulWidget {
  const MainMenuScreen({super.key});

  @override
  ConsumerState<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends ConsumerState<MainMenuScreen> {
  DateTime? _lastBack;

  /// Android : Retour depuis le menu principal ⇒ double appui pour quitter.
  void _onBack() {
    final now = DateTime.now();
    final last = _lastBack;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      unawaited(SystemNavigator.pop());
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Appuyez encore sur Retour pour quitter')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: ResponsiveBuilder(
            builder: (context, sizeClass) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: sizeClass == SizeClass.compact ? 360 : 440,
                  ),
                  child: _MenuColumn(sizeClass: sizeClass),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuColumn extends ConsumerStatefulWidget {
  const _MenuColumn({required this.sizeClass});

  final SizeClass sizeClass;

  @override
  ConsumerState<_MenuColumn> createState() => _MenuColumnState();
}

class _MenuColumnState extends ConsumerState<_MenuColumn> {
  SizeClass get sizeClass => widget.sizeClass;

  /// Une partie vient de se terminer : l'état de « Reprendre » peut avoir changé.
  Future<void> _afterGame(Future<void> game) async {
    await game;
    if (mounted) setState(() {});
  }

  String _dailyLabel() {
    final best = ref.watch(progressProvider).daily[dailyKey(DateTime.now())];
    if (best == null) return 'Défi du jour';
    return 'Défi du jour (record ${best ~/ 60} min '
        '${(best % 60).toString().padLeft(2, '0')} s)';
  }

  Future<void> _dailyChallenge() async {
    final defs = await ref.read(defsProvider.future);
    if (!mounted) return;
    final now = DateTime.now();
    await startGame(
      context,
      ref,
      dailyOptions(now, defs),
      daily: dailyKey(now),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = sizeClass.minTouchTarget + 8;
    ButtonStyle style() =>
        FilledButton.styleFrom(minimumSize: Size.fromHeight(height));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Les Royaumes du Fleuve',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 32),
        FilledButton(
          style: style(),
          onPressed: () =>
              unawaited(_afterGame(showNewGameDialog(context, ref))),
          child: const Text('Nouvelle partie'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: style(),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CampaignScreen()),
          ),
          child: const Text('Campagne'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          style: style(),
          onPressed: () => unawaited(_afterGame(_dailyChallenge())),
          child: Text(_dailyLabel()),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          style: style(),
          onPressed: ref.read(saveStoreProvider)?.newestSlot() == null
              ? null
              : () => unawaited(_afterGame(resumeGame(context, ref))),
          child: const Text('Reprendre la partie'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          style: style(),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const OptionsScreen()),
          ),
          child: const Text('Options'),
        ),
        if (Platform.isWindows) ...<Widget>[
          const SizedBox(height: 12),
          FilledButton.tonal(
            style: style(),
            onPressed: () => ref.read(closeCoordinatorProvider).requestClose(),
            child: const Text('Quitter'),
          ),
        ],
      ],
    );
  }
}

/// Options (Phase 0) : plein écran (Windows) et échelle d'interface.
class OptionsScreen extends ConsumerStatefulWidget {
  const OptionsScreen({super.key});

  @override
  ConsumerState<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends ConsumerState<OptionsScreen> {
  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(uiScaleProvider);
    final window = ref.watch(windowServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Options')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (Platform.isWindows)
              SwitchListTile(
                title: const Text('Plein écran (F11)'),
                value: window.isFullScreen,
                onChanged: (value) async {
                  await window.setFullScreen(value: value);
                  if (mounted) setState(() {});
                },
              ),
            ListTile(
              title: Text(
                "Échelle de l'interface : ${(scale * 100).round()} %",
              ),
              subtitle: Slider(
                min: kMinUiScale,
                max: kMaxUiScale,
                divisions: 14,
                value: clampUiScale(scale),
                onChanged: (v) =>
                    ref.read(uiScaleProvider.notifier).state = clampUiScale(v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
