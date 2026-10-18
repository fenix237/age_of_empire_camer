import 'dart:io';

/// Verrou de fichier : garantit qu'une seule instance du jeu écrit dans le
/// dossier de données (sauvegardes, journal).
///
/// Limite connue (Phase 0) : la seconde instance se ferme sans ramener la
/// première au premier plan. Ce point demande du code natif Windows ; il est
/// repris à la Phase 10.
class SingleInstanceLock {
  SingleInstanceLock(this._dir);

  final Directory _dir;
  RandomAccessFile? _handle;

  /// Retourne `true` si le verrou est obtenu. En cas d'impossibilité de créer
  /// le verrou (dossier inaccessible), on laisse jouer plutôt que de bloquer.
  bool tryAcquire() {
    try {
      _dir.createSync(recursive: true);
      final file = File('${_dir.path}/app.lock');
      final handle = file.openSync(mode: FileMode.write);
      try {
        // Non bloquant : lève une exception si déjà verrouillé.
        handle.lockSync();
      } on FileSystemException {
        handle.closeSync();
        return false;
      }
      _handle = handle;
      return true;
    } on FileSystemException {
      return true;
    }
  }

  void release() {
    final handle = _handle;
    if (handle == null) return;
    try {
      handle
        ..unlockSync()
        ..closeSync();
    } on FileSystemException {
      // Le système libère le verrou à la fermeture du processus.
    }
    _handle = null;
  }
}
