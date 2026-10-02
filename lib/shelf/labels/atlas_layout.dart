import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Design units used by every label painter: 1 unit = 0.1 mm of printed
/// board. Painting in physical units (instead of pixels) is what makes the
/// shelf atlas and the hero atlas pixel-for-pixel the same design at two
/// resolutions.
const double kUnitsPerMm = 10;

/// One printed surface inside an atlas.
@immutable
class AtlasRegion {
  const AtlasRegion({
    required this.name,
    required this.normRect,
    required this.sizeMm,
  });

  factory AtlasRegion.fromJson(String name, Map<String, dynamic> j) {
    final mm = (j['mm'] as List).cast<num>();
    return AtlasRegion(
      name: name,
      normRect: Rect.fromLTWH(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['w'] as num).toDouble(),
        (j['h'] as num).toDouble(),
      ),
      sizeMm: Size(mm[0].toDouble(), mm[1].toDouble()),
    );
  }

  final String name;

  /// Normalised x, y, w, h in image space (origin top-left, y down).
  final Rect normRect;

  /// Printed size of the region.
  final Size sizeMm;

  /// The region inside an atlas of [atlasSize] (pixels or design units).
  Rect rectIn(Size atlasSize) => Rect.fromLTWH(
        normRect.left * atlasSize.width,
        normRect.top * atlasSize.height,
        normRect.width * atlasSize.width,
        normRect.height * atlasSize.height,
      );

  @override
  bool operator ==(Object other) =>
      other is AtlasRegion &&
      other.name == name &&
      other.normRect == normRect &&
      other.sizeMm == sizeMm;

  @override
  int get hashCode => Object.hash(name, normRect, sizeMm);

  @override
  String toString() => 'AtlasRegion($name, $normRect, ${sizeMm}mm)';
}

/// One atlas layout (`spine` or `hero`).
@immutable
class AtlasLayout {
  const AtlasLayout({
    required this.name,
    required this.canvasMm,
    required this.regions,
  });

  factory AtlasLayout.fromJson(String name, Map<String, dynamic> j) {
    final c = (j['canvas_mm'] as List).cast<num>();
    final regions = <String, AtlasRegion>{};
    (j['regions'] as Map<String, dynamic>).forEach((k, v) {
      regions[k] = AtlasRegion.fromJson(k, v as Map<String, dynamic>);
    });
    return AtlasLayout(
      name: name,
      canvasMm: Size(c[0].toDouble(), c[1].toDouble()),
      regions: Map.unmodifiable(regions),
    );
  }

  final String name;
  final Size canvasMm;
  final Map<String, AtlasRegion> regions;

  /// The whole canvas in design units (0.1 mm).
  Size get designSize =>
      Size(canvasMm.width * kUnitsPerMm, canvasMm.height * kUnitsPerMm);

  AtlasRegion region(String name) {
    final r = regions[name];
    if (r == null) {
      throw ArgumentError.value(
          name, 'name', 'no such region in layout "${this.name}"');
    }
    return r;
  }

  /// Region rect in design units.
  Rect designRect(String name) => region(name).rectIn(designSize);

  /// Region rect in pixels for an atlas rendered at [pixelSize].
  Rect pixelRect(String name, Size pixelSize) =>
      region(name).rectIn(pixelSize);

  /// Pixel size of an atlas [widthPx] wide (height follows the canvas).
  Size pixelSizeForWidth(int widthPx) => Size(
        widthPx.toDouble(),
        (widthPx * canvasMm.height / canvasMm.width).roundToDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is AtlasLayout &&
      other.name == name &&
      other.canvasMm == canvasMm &&
      mapEquals(other.regions, regions);

  @override
  int get hashCode => Object.hash(name, canvasMm, Object.hashAll(regions.values));

  @override
  String toString() => 'AtlasLayout($name, ${canvasMm}mm, ${regions.keys})';
}

/// Parsed `assets/plates/manifest.json`: the atlas layouts the label
/// composer paints into. Accepts both the v1 layout (layouts at the top
/// level) and v2 (layouts under `"atlas"`, alongside the plate `groups` and
/// `plates`, which the composer doesn't need).
@immutable
class AtlasManifest {
  const AtlasManifest({
    required this.version,
    required this.layouts,
    required this.sleeveMm,
  });

  factory AtlasManifest.fromJson(Map<String, dynamic> j) {
    final atlas = (j['atlas'] as Map<String, dynamic>?) ?? j;
    final layouts = <String, AtlasLayout>{};
    atlas.forEach((k, v) {
      if (v is Map<String, dynamic> && v['canvas_mm'] is List && v['regions'] is Map) {
        layouts[k] = AtlasLayout.fromJson(k, v);
      }
    });
    if (!layouts.containsKey('hero') || !layouts.containsKey('spine')) {
      throw const FormatException('manifest has no "hero"/"spine" atlas layouts');
    }
    final s = ((atlas['sleeve_mm'] ?? j['sleeve_mm']) as List?)?.cast<num>();
    return AtlasManifest(
      version: (j['version'] as num?)?.toInt() ?? 1,
      layouts: Map.unmodifiable(layouts),
      sleeveMm: s == null
          ? const <double>[107, 190.5, 28]
          : List.unmodifiable(s.map((e) => e.toDouble())),
    );
  }

  /// Parses the manifest from its JSON text (used by tests and [load]).
  factory AtlasManifest.parse(String jsonText) =>
      AtlasManifest.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);

  /// Loads the manifest from an asset bundle. The asset must be listed in
  /// pubspec.yaml; until it is, use [standard] (an embedded copy).
  static Future<AtlasManifest> load(
    AssetBundle bundle, {
    String key = 'assets/plates/manifest.json',
  }) async =>
      AtlasManifest.parse(await bundle.loadString(key));

  final int version;

  /// Every atlas layout in the manifest ("hero", "spine", and any others
  /// the plate pipeline adds, e.g. "tag").
  final Map<String, AtlasLayout> layouts;

  /// Sleeve front width, height and spine depth in mm.
  final List<double> sleeveMm;

  AtlasLayout get hero => layouts['hero']!;
  AtlasLayout get spine => layouts['spine']!;

  /// Width of one sleeve face (front/back) in mm.
  double get faceWidthMm => sleeveMm[0];

  /// Embedded copy of the composer's part of `assets/plates/manifest.json`
  /// (v2, generated by `blender/nc/atlas.py`): the `hero` and `spine`
  /// layouts. A test keeps them in sync with the file; other layouts the
  /// plate pipeline adds (`tag`, `dvd`…) are parsed but not needed here.
  static final AtlasManifest standard = AtlasManifest.parse(standardJson);

  static const String standardJson = '''
{
  "version": 2,
  "atlas": {
    "hero": {
      "canvas_mm": [256.0, 256.0],
      "regions": {
        "back": {"x": 0.0, "y": 0.0, "w": 0.41796875, "h": 0.744140625, "mm": [107.0, 190.5]},
        "spine": {"x": 0.41796875, "y": 0.0, "w": 0.109375, "h": 0.744140625, "mm": [28.0, 190.5]},
        "front": {"x": 0.52734375, "y": 0.0, "w": 0.41796875, "h": 0.744140625, "mm": [107.0, 190.5]},
        "cassette_face": {"x": 0.0, "y": 0.76953125, "w": 0.30859375, "h": 0.16796875, "mm": [79.0, 43.0]},
        "cassette_spine": {"x": 0.3359375, "y": 0.76953125, "w": 0.57421875, "h": 0.07421875, "mm": [147.0, 19.0]}
      }
    },
    "spine": {
      "canvas_mm": [48.0, 190.5],
      "regions": {
        "spine": {"x": 0.0, "y": 0.0, "w": 0.5833333333333334, "h": 1.0, "mm": [28.0, 190.5]},
        "front_strip": {"x": 0.5833333333333334, "y": 0.0, "w": 0.4166666666666667, "h": 1.0, "mm": [20.0, 190.5]}
      }
    },
    "sleeve_mm": [107.0, 190.5, 28.0]
  }
}
''';

  @override
  bool operator ==(Object other) =>
      other is AtlasManifest &&
      other.version == version &&
      mapEquals(other.layouts, layouts) &&
      listEquals(other.sleeveMm, sleeveMm);

  @override
  int get hashCode =>
      Object.hash(version, Object.hashAllUnordered(layouts.values), Object.hashAll(sleeveMm));
}