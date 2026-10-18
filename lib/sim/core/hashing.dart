import 'dart:typed_data';

/// Hash FNV-1a 64 bits, alimenté par des entiers (hash d'état de simulation).
class StateHasher {
  int _h = -3750763034362895579; // 0xCBF29CE484222325

  void addInt(int v) {
    // On injecte les 8 octets de l'entier pour rester indépendant de la taille.
    var x = v;
    for (var i = 0; i < 8; i++) {
      _h = (_h ^ (x & 0xFF)) * 1099511628211;
      x >>>= 8;
    }
  }

  void addInts(Iterable<int> values) {
    values.forEach(addInt);
  }

  void addBytes(Uint8List bytes) {
    addInt(bytes.length);
    for (final b in bytes) {
      _h = (_h ^ b) * 1099511628211;
    }
  }

  int get value => _h;
}

/// CRC-32 (IEEE 802.3) pour l'intégrité des sauvegardes.
abstract final class Crc32 {
  static final Uint32List _table = () {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      }
      t[n] = c;
    }
    return t;
  }();

  static int compute(List<int> bytes, [int start = 0, int? end]) {
    var c = 0xFFFFFFFF;
    final stop = end ?? bytes.length;
    for (var i = start; i < stop; i++) {
      c = _table[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    }
    return c ^ 0xFFFFFFFF;
  }
}

/// Hash 64 bits affiché en hexadécimal non signé (16 chiffres).
String hex64(int v) =>
    '${(v >>> 32).toRadixString(16).padLeft(8, '0')}'
    '${(v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';
