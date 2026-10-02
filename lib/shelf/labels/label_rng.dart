/// Deterministic, platform-stable pseudo random numbers for label design.
///
/// `dart:math` Random is not guaranteed to produce the same sequence on the
/// VM and on the web, and plain `*` overflows differently there (JS numbers
/// lose precision past 2^53). Everything here is done in 32-bit unsigned
/// arithmetic with a split multiply, so a title prints the same tape on
/// Android, iOS and web.
library;

const int _mask32 = 0xFFFFFFFF;

/// 32-bit multiply (like JS `Math.imul`, unsigned result) that never needs
/// more than 48 bits of intermediate precision.
int imul32(int a, int b) {
  a &= _mask32;
  b &= _mask32;
  final lo = (a & 0xFFFF) * b;
  final hi = ((a >>> 16) * b) & 0xFFFF;
  return (lo + ((hi << 16) & _mask32)) & _mask32;
}

/// FNV-1a over UTF-16 code units, finished with a murmur-style avalanche so
/// near-identical ids ("series-1", "series-2") land far apart.
int hashString(String s) {
  var h = 0x811C9DC5;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = imul32(h, 0x01000193);
  }
  h ^= h >>> 16;
  h = imul32(h, 0x85EBCA6B);
  h ^= h >>> 13;
  h = imul32(h, 0xC2B2AE35);
  h ^= h >>> 16;
  return h & _mask32;
}

/// Mulberry32 generator.
class LabelRng {
  LabelRng(int seed) : _state = seed & _mask32;

  /// Seeded from a title id plus an optional salt ("spine", "wear-front"…),
  /// so independent design decisions don't shift when one of them changes.
  factory LabelRng.forTitle(String titleId, [String salt = '']) =>
      LabelRng(hashString(salt.isEmpty ? titleId : '$titleId#$salt'));

  int _state;

  /// Next unsigned 32-bit value.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _mask32;
    var t = _state;
    t = imul32(t ^ (t >>> 15), t | 1);
    t ^= (t + imul32(t ^ (t >>> 7), t | 61)) & _mask32;
    return (t ^ (t >>> 14)) & _mask32;
  }

  /// Uniform in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Uniform in [min, max).
  double range(double min, double max) => min + (max - min) * nextDouble();

  /// Uniform integer in [0, n).
  int nextInt(int n) => n <= 1 ? 0 : (nextDouble() * n).floor().clamp(0, n - 1);

  bool chance(double p) => nextDouble() < p;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  /// Signed jitter in [-amount, amount).
  double jitter(double amount) => (nextDouble() * 2 - 1) * amount;
}
