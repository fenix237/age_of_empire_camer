import 'dart:async';

import 'package:age_of_empire_camer/app/logging/app_logger.dart';

/// Réponse de l'utilisateur à une demande de fermeture.
enum CloseDecision {
  /// Sauvegarder puis quitter.
  saveAndQuit,

  /// Quitter sans sauvegarder.
  quitWithoutSaving,

  /// Rester dans le jeu.
  cancel,
}

/// Contrat d'un écran/partie qui peut avoir des données non sauvegardées.
abstract interface class CloseGuard {
  /// Y a-t-il des changements non sauvegardés ?
  bool get hasUnsavedChanges;

  /// Demande à l'utilisateur quoi faire (dialogue). La partie est mise en
  /// pause pendant la question.
  Future<CloseDecision> askUser();

  /// Sauvegarde. Retourne `false` en cas d'échec (disque plein, etc.).
  Future<bool> save();
}

/// Orchestre TOUTES les fermetures (✕, Alt+F4, menu, arrêt de session).
///
/// Garanties :
/// - une seule séquence de fermeture à la fois ;
/// - la sauvegarde réussit avant de quitter, sinon la fermeture est annulée
///   (sauf `force`, utilisé quand le système impose l'arrêt) ;
/// - les ressources sont libérées dans l'ordre inverse de l'enregistrement.
class CloseCoordinator {
  CloseCoordinator({required Future<void> Function() terminate})
    : _terminate = terminate;

  final Future<void> Function() _terminate;
  final List<Future<void> Function()> _disposers = [];
  CloseGuard? _guard;
  bool _closing = false;

  /// Écran/partie actuellement actif (un seul garde à la fois).
  // ignore: use_setters_to_change_properties
  void setGuard(CloseGuard? guard) => _guard = guard;

  /// Enregistre une action de nettoyage, exécutée à la fermeture.
  void addDisposer(Future<void> Function() disposer) =>
      _disposers.add(disposer);

  /// Demande de fermeture. Retourne `true` si l'application se ferme.
  ///
  /// [force] : le système impose l'arrêt (fermeture de session) ; pas de
  /// dialogue, sauvegarde rapide seulement.
  Future<bool> requestClose({bool force = false}) async {
    if (_closing) return false;
    _closing = true;
    try {
      final guard = _guard;
      if (guard != null && guard.hasUnsavedChanges) {
        if (force) {
          await _safeSave(guard);
        } else {
          final decision = await guard.askUser();
          switch (decision) {
            case CloseDecision.cancel:
              _closing = false;
              return false;
            case CloseDecision.saveAndQuit:
              final ok = await _safeSave(guard);
              if (!ok) {
                // Échec de sauvegarde : on n'abandonne jamais les données.
                _closing = false;
                return false;
              }
            case CloseDecision.quitWithoutSaving:
              break;
          }
        }
      }
      await _runDisposers();
      await _terminate();
      return true;
    } on Object catch (e, s) {
      AppLogger.instance.error('Erreur pendant la fermeture', e, s);
      _closing = false;
      return false;
    }
  }

  Future<bool> _safeSave(CloseGuard guard) async {
    try {
      return await guard.save();
    } on Object catch (e, s) {
      AppLogger.instance.error('Sauvegarde de fermeture échouée', e, s);
      return false;
    }
  }

  Future<void> _runDisposers() async {
    for (final disposer in _disposers.reversed) {
      try {
        await disposer();
      } on Object catch (e, s) {
        AppLogger.instance.error('Nettoyage échoué', e, s);
      }
    }
    _disposers.clear();
  }
}
