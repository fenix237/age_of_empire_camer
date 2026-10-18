import 'dart:io';
import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/save/save_codec.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Emplacements de sauvegarde sur disque, écriture atomique :
/// `slot.tmp` → vérification → `slot.sav` (l'ancien devient `slot.bak`).
class SaveStore {
  SaveStore(this.dir);

  final Directory dir;

  File _sav(String slot) => File('${dir.path}/$slot.sav');
  File _bak(String slot) => File('${dir.path}/$slot.bak');
  File _tmp(String slot) => File('${dir.path}/$slot.tmp');

  static final RegExp _validSlot = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

  void _checkSlot(String slot) {
    if (!_validSlot.hasMatch(slot)) {
      throw ArgumentError.value(slot, 'slot', 'nom d’emplacement invalide');
    }
  }

  /// Écrit atomiquement. Lève en cas d'échec (disque plein…) sans toucher à
  /// la sauvegarde précédente.
  Future<void> write(String slot, Uint8List bytes) async {
    _checkSlot(slot);
    await dir.create(recursive: true);
    final tmp = _tmp(slot);
    await tmp.writeAsBytes(bytes, flush: true);
    // Vérification : le fichier relu doit être identique et valide.
    final back = await tmp.readAsBytes();
    if (back.length != bytes.length) {
      await tmp.delete();
      throw const FileSystemException('Écriture incomplète');
    }
    SaveCodec.readPayload(back);
    final sav = _sav(slot);
    if (sav.existsSync()) {
      final bak = _bak(slot);
      if (bak.existsSync()) await bak.delete();
      await sav.rename(bak.path);
    }
    await tmp.rename(sav.path);
  }

  Future<void> saveWorld(String slot, World w) =>
      write(slot, SaveCodec.encode(w));

  /// Charge un monde ; bascule sur `.bak` si la sauvegarde principale est
  /// corrompue. Renvoie null si rien n'est exploitable.
  Future<World?> loadWorld(Defs defs, String slot) async {
    _checkSlot(slot);
    for (final f in <File>[_sav(slot), _bak(slot)]) {
      if (!f.existsSync()) continue;
      try {
        return SaveCodec.decode(defs, await f.readAsBytes());
      } on SaveException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  bool exists(String slot) {
    _checkSlot(slot);
    return _sav(slot).existsSync() || _bak(slot).existsSync();
  }

  Future<void> delete(String slot) async {
    _checkSlot(slot);
    for (final f in <File>[_sav(slot), _bak(slot), _tmp(slot)]) {
      if (f.existsSync()) await f.delete();
    }
  }

  /// Autosauvegarde tournante : `prefix_0`, `prefix_1`, … (le plus ancien
  /// est remplacé). Renvoie l'emplacement utilisé.
  Future<String> writeRotating(String prefix, int count, World w) async {
    var oldest = '${prefix}_0';
    DateTime? oldestTime;
    for (var i = 0; i < count; i++) {
      final slot = '${prefix}_$i';
      final f = _sav(slot);
      if (!f.existsSync()) {
        oldest = slot;
        oldestTime = null;
        break;
      }
      final t = f.lastModifiedSync();
      if (oldestTime == null || t.isBefore(oldestTime)) {
        oldestTime = t;
        oldest = slot;
      }
    }
    await saveWorld(oldest, w);
    return oldest;
  }

  /// Emplacement le plus récemment écrit (reprise d'une partie), ou null.
  String? newestSlot() {
    String? best;
    DateTime? bestTime;
    for (final s in slots()) {
      final t = _sav(s).lastModifiedSync();
      if (bestTime == null || t.isAfter(bestTime)) {
        bestTime = t;
        best = s;
      }
    }
    return best;
  }

  /// Emplacements présents (sans extension), triés par nom.
  List<String> slots() {
    if (!dir.existsSync()) return <String>[];
    final names = <String>{};
    for (final e in dir.listSync()) {
      final name = e.uri.pathSegments.last;
      if (name.endsWith('.sav')) names.add(name.substring(0, name.length - 4));
    }
    return names.toList()..sort();
  }
}
