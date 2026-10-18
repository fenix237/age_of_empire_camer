import 'dart:convert';
import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/core/hashing.dart';
import 'package:age_of_empire_camer/sim/core/invariants.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

enum SaveError { badMagic, tooNew, truncated, corrupt, invalid, tooLarge }

class SaveException implements Exception {
  SaveException(this.error, [this.detail = '']);

  final SaveError error;
  final String detail;

  @override
  String toString() => 'SaveException(${error.name}) $detail';
}

/// Format de sauvegarde versionné avec somme de contrôle CRC-32.
///
/// En-tête (16 octets, big-endian) :
/// `RDFS` | version de format (u16) | réservé (u16) | longueur (u32) | CRC32 (u32)
/// suivi de la charge utile JSON UTF-8.
abstract final class SaveCodec {
  static const List<int> magic = <int>[0x52, 0x44, 0x46, 0x53]; // "RDFS"
  static const int formatVersion = 1;
  static const int headerSize = 16;

  /// Borne dure : un fichier de sauvegarde ne dépasse jamais cette taille.
  static const int maxPayload = 64 * 1024 * 1024;

  /// Migrations : clé = version source, valeur = fonction vers version + 1.
  static final Map<int, Map<String, dynamic> Function(Map<String, dynamic>)>
  migrations = <int, Map<String, dynamic> Function(Map<String, dynamic>)>{};

  static Uint8List encode(World w) {
    final payload = utf8.encode(jsonEncode(w.toJson()));
    final out = Uint8List(headerSize + payload.length);
    final bd = ByteData.view(out.buffer)
      ..setUint16(4, formatVersion)
      ..setUint16(6, 0)
      ..setUint32(8, payload.length)
      ..setUint32(12, Crc32.compute(payload));
    out.setRange(0, 4, magic);
    out.setRange(headerSize, out.length, payload);
    assert(bd.lengthInBytes == out.length, 'en-tête cohérent');
    return out;
  }

  /// Lit l'en-tête et vérifie l'intégrité sans construire le monde.
  static Map<String, dynamic> readPayload(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw SaveException(SaveError.truncated, 'en-tête incomplet');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != magic[i]) throw SaveException(SaveError.badMagic);
    }
    final bd = ByteData.sublistView(bytes);
    final version = bd.getUint16(4);
    final length = bd.getUint32(8);
    final crc = bd.getUint32(12);
    if (version > formatVersion) {
      throw SaveException(
        SaveError.tooNew,
        'sauvegarde v$version, application v$formatVersion',
      );
    }
    if (length > maxPayload) throw SaveException(SaveError.tooLarge);
    if (bytes.length < headerSize + length) {
      throw SaveException(SaveError.truncated, 'charge utile incomplète');
    }
    final payload = Uint8List.sublistView(
      bytes,
      headerSize,
      headerSize + length,
    );
    if (Crc32.compute(payload) != crc) {
      throw SaveException(SaveError.corrupt, 'CRC invalide');
    }
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map<String, dynamic>) {
        throw SaveException(SaveError.invalid, 'racine non objet');
      }
      json = decoded;
    } on FormatException catch (e) {
      throw SaveException(SaveError.invalid, e.message);
    }
    for (var v = version; v < formatVersion; v++) {
      final m = migrations[v];
      if (m == null) {
        throw SaveException(SaveError.invalid, 'migration $v manquante');
      }
      json = m(json);
    }
    return json;
  }

  static World decode(Defs defs, Uint8List bytes) {
    final json = readPayload(bytes);
    try {
      final world = World.fromJson(defs, json);
      final problems = validateStructure(world);
      if (problems.isNotEmpty) {
        throw SaveException(SaveError.invalid, problems.first);
      }
      return world;
    } on SaveException {
      rethrow;
    } on DataException catch (e) {
      throw SaveException(SaveError.invalid, e.toString());
    } on Object catch (e) {
      // Tout contenu mal formé est une sauvegarde invalide, jamais un crash.
      throw SaveException(SaveError.invalid, e.toString());
    }
  }
}
