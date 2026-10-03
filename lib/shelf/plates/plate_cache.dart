import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'image_lru.dart';
import 'plate_manifest.dart';

/// Decoded plate images, loaded from the asset bundle and decoded once.
///
/// ## Texture memory budget (decoded RGBA, 4 bytes per pixel)
///
/// | what | size each | count | total | owner |
/// |---|---|---|---|---|
/// | shelf plates: `bay_0..2` | 1116×690 = 3.08 MB | 3 | 9.24 MB | shelf plate cache (this class, 24 MiB budget) |
/// | shelf plates: `rail` (colour, uv, uv2) | 1068×95 = 0.41 MB | 3 | 1.22 MB | 〃 |
/// | shelf plates: `tape_a..d`, `sealed`, `pulled` | 86×690 = 0.24 MB | 6×3 | 4.27 MB | 〃 |
/// | shelf plates: `tape_pulled_shadow`, `tape_end_shadow` | 258×690 = 0.71 MB | 2 | 1.42 MB | 〃 |
/// | shelf plates: `tape_lean` | 670×653 = 1.75 MB | 3 | 5.25 MB | 〃 |
/// | **all shelf plates** | | | **21.4 MB** | resident while the app uses a shelf |
/// | hero sources: one `rot_NN` frame (36 in a turn) | 640×900 = 2.30 MB | 3 | 6.9 MB | hero plate cache (28 MiB budget), evicted as soon as the frame is composited |
/// | hero sources: `front_hi` | 1280×1800 = 9.22 MB | 3 | 27.6 MB | 〃, composited once per atlas |
/// | hero sources: one `cassette_pNNN` | 900×620 = 2.23 MB | 3 | 6.7 MB | 〃 |
/// | composed shelf rows | ≤ 1674×1035 = 6.9 MB; phone (3×, 393 dp) 1179×729 = 3.4 MB + rail 0.45 MB | | ≤ 28 MiB | `ShelfRenderer` row LRU (≈ 7 phone rows) |
/// | spine label art | 144 px × on-screen scale wide; phone 152×603 = 0.37 MB | | ≤ 12 MiB | `ShelfRenderer` art LRU (≈ 34 tapes) |
/// | rail card art | 1056×57 × scale = 0.24 MB | | ≤ 3 MiB | `ShelfRenderer` tag LRU |
/// | shelf label artwork in flight | poster 340 w (0.7 MB) + logo 400 w (≤ 0.25 MB) | per tape being labelled | — | `TapeCatalog`, released when its spine is painted |
/// | inspect: artwork in flight | poster 680×1000 2.7 MB, logo 800 w 1 MB, banner 760×140 0.4 MB, fanart 960×540 2.1 MB | 1 title | ≈ 6.2 MB | `TapeCatalog`, released when the atlas is painted |
/// | inspect: hero label atlas | 1536² = 9.4 MB | 1 | 9.4 MB | `HeroFrames`, freed on close |
/// | inspect: composited rotation frames | ≤ 640×900 = 2.3 MB (display-capped) | | ≤ 24 MiB | `HeroFrames` LRU (≈ 10 frames around the view), freed on close |
/// | inspect: composited front (`front_hi`) | ≤ 1280×1800 = 9.2 MB (display-capped; phone 3× ≈ 870×1220 = 4.3 MB) | 1 | ≤ 9.2 MB | `HeroFrames`, freed on close |
/// | inspect: composited cassette | 132 dp × dpr wide; phone 396×273 = 0.43 MB | 1 | ≤ 2.2 MB | `HeroFrames`, freed on close |
///
/// Steady state while browsing a shelf: ≈ 21 MB plates + ≤ 28 MiB rows +
/// ≤ 12 MiB art + ≤ 3 MiB cards ≈ 65 MB at most. The inspect view adds
/// ≈ 45 MB at most while open (+ a transient ≤ 28 MiB while `front_hi` is
/// composited), all of it released on close.
///
/// Measured on the web release build (CanvasKit, 375×812 @3×, demo
/// account): the CanvasKit heap stays at 33.5 MB with the collection open
/// and peaks at 134 MB with the inspect view open, unchanged through
/// repeated full turns (most decoded images live as GPU textures there).
///
/// Images on screen are held as clones by their widgets, so an eviction
/// never pulls a texture out from under a frame; it just stops it being
/// reused.
class PlateImageCache {
  PlateImageCache({AssetBundle? bundle, required int budgetBytes})
      : _bundle = bundle,
        _lru = ImageLru<String>(budgetBytes: budgetBytes);

  /// Shelf plates: everything fits (21.4 MB), so they stay resident.
  static const int shelfBudgetBytes = 24 << 20;

  /// Hero sources: enough for `front_hi`'s three images at once (27.6 MB).
  static const int heroBudgetBytes = 28 << 20;

  final AssetBundle? _bundle;
  final ImageLru<String> _lru;
  final Map<String, Future<void>> _pending = {};

  AssetBundle get bundle => _bundle ?? rootBundle;

  int get bytes => _lru.bytes;

  /// The decoded image at [path] (relative to [PlateManifest.assetRoot])
  /// if it is resident. The handle belongs to the cache: draw it now, or
  /// `clone()` it to keep it.
  ui.Image? peek(String path) => _lru.get(path);

  /// The decoded image at [path], as a clone the caller owns and must
  /// dispose.
  Future<ui.Image> acquire(String path) async {
    for (var attempt = 0;; attempt++) {
      final hit = _lru.get(path);
      if (hit != null) return hit.clone();
      if (attempt == 3) {
        // Thrashing: more is in flight than the budget holds. Serve this
        // caller without caching rather than decoding forever.
        return _decodeImage(path);
      }
      await (_pending[path] ??= _decode(path).whenComplete(() {
        // Block body on purpose: `remove` returns this very future, and
        // whenComplete would wait on it.
        _pending.remove(path);
      }));
    }
  }

  /// All three images of [spec] (colour plus the UV pair when it carries a
  /// label), as caller-owned clones.
  Future<PlateImages> acquirePlate(PlateSpec spec) async {
    final images = await Future.wait([for (final p in spec.paths) acquire(p)]);
    return PlateImages(
      spec: spec,
      color: images[0],
      uv: spec.hasLabel ? images[1] : null,
      uv2: spec.hasLabel ? images[2] : null,
    );
  }

  /// Makes sure [paths] are decoded and resident.
  Future<void> warm(Iterable<String> paths) async {
    final images = await Future.wait([for (final p in paths) acquire(p)]);
    for (final i in images) {
      i.dispose();
    }
  }

  /// Whether every one of [paths] is resident right now.
  bool hasAll(Iterable<String> paths) => paths.every(_lru.containsKey);

  /// Drops [path] from the cache (clones handed out stay valid).
  void evict(String path) => _lru.remove(path);

  void evictPlate(PlateSpec spec) => spec.paths.forEach(evict);

  void clear() => _lru.clear();

  Future<void> _decode(String path) async {
    _lru.put(path, await _decodeImage(path));
  }

  Future<ui.Image> _decodeImage(String path) async {
    final data = await bundle.load('${PlateManifest.assetRoot}$path');
    // No target size: the UV planes must keep every byte as rendered.
    final buffer = await ui.ImmutableBuffer.fromUint8List(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    // The codec takes ownership of (and disposes) the buffer.
    final codec = await ui.instantiateImageCodecFromBuffer(buffer);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  @visibleForTesting
  Iterable<String> get residentPaths => _lru.keys;
}

/// Caller-owned handles to one plate's images.
class PlateImages {
  PlateImages({required this.spec, required this.color, this.uv, this.uv2});

  final PlateSpec spec;
  final ui.Image color;
  final ui.Image? uv;
  final ui.Image? uv2;

  bool get hasLabel => uv != null && uv2 != null;

  void dispose() {
    color.dispose();
    uv?.dispose();
    uv2?.dispose();
  }
}
