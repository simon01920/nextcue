import 'dart:collection';
import 'dart:ui' as ui;

/// Byte-budgeted LRU of [ui.Image]s.
///
/// The cache owns one handle per entry and disposes it on eviction. [get]
/// returns that handle for immediate, synchronous use (drawing it now);
/// anything that keeps an image past the current frame must keep a
/// `clone()` and dispose it itself. The underlying texture is freed only
/// when every handle is gone, so evicting an image that is still on screen
/// is safe; it just stops being reusable.
class ImageLru<K> {
  ImageLru({required this.budgetBytes, this.maxEntries});

  /// Decoded bytes (4 per pixel) the cache may hold before evicting.
  final int budgetBytes;
  final int? maxEntries;

  final LinkedHashMap<K, ui.Image> _map = LinkedHashMap<K, ui.Image>();
  int _bytes = 0;

  static int bytesOf(ui.Image image) => image.width * image.height * 4;

  /// Decoded bytes currently held.
  int get bytes => _bytes;
  int get length => _map.length;
  Iterable<K> get keys => _map.keys;

  bool containsKey(K key) => _map.containsKey(key);

  /// The cached image (marked most recently used), or null.
  ui.Image? get(K key) {
    final image = _map.remove(key);
    if (image == null) return null;
    _map[key] = image;
    return image;
  }

  /// Takes ownership of [image].
  void put(K key, ui.Image image) {
    remove(key);
    _map[key] = image;
    _bytes += bytesOf(image);
    _trim();
  }

  void remove(K key) {
    final old = _map.remove(key);
    if (old == null) return;
    _bytes -= bytesOf(old);
    old.dispose();
  }

  void removeWhere(bool Function(K key) test) {
    for (final k in _map.keys.where(test).toList()) {
      remove(k);
    }
  }

  void _trim() {
    // The newest entry always survives, even when it alone is over budget.
    while (_map.length > 1 &&
        (_bytes > budgetBytes ||
            (maxEntries != null && _map.length > maxEntries!))) {
      remove(_map.keys.first);
    }
  }

  void clear() {
    for (final image in _map.values) {
      image.dispose();
    }
    _map.clear();
    _bytes = 0;
  }
}
