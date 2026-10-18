/// Arithmétique en virgule fixe : 1 case = 256 unités (`Fx.one`).
///
/// Aucun `double` dans la simulation : `sin/cos/sqrt` flottants ne sont pas
/// garantis identiques entre x64 et ARM. Tout passe par des entiers.
abstract final class Fx {
  static const int bits = 8;
  static const int one = 1 << bits;
  static const int half = one >> 1;

  static int fromInt(int tiles) => tiles << bits;

  /// Partie entière (arrondi vers le bas, y compris pour les négatifs).
  static int toInt(int fx) => fx >> bits;

  /// Centre de la case [tile] en virgule fixe.
  static int tileCenter(int tile) => (tile << bits) + half;

  static int mul(int a, int b) => (a * b) >> bits;

  static int div(int a, int b) => (a << bits) ~/ b;

  /// Racine carrée entière (plancher) d'un entier positif.
  static int isqrt(int n) {
    if (n <= 0) return 0;
    if (n < 4) return 1;
    var x = n;
    var y = (x + 1) >> 1;
    while (y < x) {
      x = y;
      y = (x + n ~/ x) >> 1;
    }
    return x;
  }

  /// Table de sinus pour 0°..90° en Q16 (65536 = 1.0).
  static const List<int> _sinQ16 = <int>[
    0,
    1144,
    2287,
    3430,
    4572,
    5712,
    6850,
    7987,
    9121,
    10252,
    11380,
    12505,
    13626,
    14742,
    15855,
    16962,
    18064,
    19161,
    20252,
    21336,
    22415,
    23486,
    24550,
    25607,
    26656,
    27697,
    28729,
    29753,
    30767,
    31772,
    32768,
    33754,
    34729,
    35693,
    36647,
    37590,
    38521,
    39441,
    40348,
    41243,
    42126,
    42995,
    43852,
    44695,
    45525,
    46341,
    47143,
    47930,
    48703,
    49461,
    50203,
    50931,
    51643,
    52339,
    53020,
    53684,
    54332,
    54963,
    55578,
    56175,
    56756,
    57319,
    57865,
    58393,
    58903,
    59396,
    59870,
    60326,
    60764,
    61183,
    61584,
    61966,
    62328,
    62672,
    62997,
    63303,
    63589,
    63856,
    64104,
    64332,
    64540,
    64729,
    64898,
    65048,
    65177,
    65287,
    65376,
    65446,
    65496,
    65526,
    65536,
  ];

  /// Sinus d'un angle en degrés entiers, résultat en Q16.
  static int sinQ16(int degrees) {
    final d = ((degrees % 360) + 360) % 360;
    if (d <= 90) return _sinQ16[d];
    if (d <= 180) return _sinQ16[180 - d];
    if (d <= 270) return -_sinQ16[d - 180];
    return -_sinQ16[360 - d];
  }

  static int cosQ16(int degrees) => sinQ16(degrees + 90);

  /// Sinus en virgule fixe (`Fx.one` = 1.0).
  static int sin(int degrees) => sinQ16(degrees) >> 8;

  static int cos(int degrees) => cosQ16(degrees) >> 8;
}
