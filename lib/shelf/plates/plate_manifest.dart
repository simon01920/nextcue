import 'dart:convert';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// `assets/plates/manifest.json` (version 2), the contract between the
/// Blender renders and the app. See docs/PLATES.md.
@immutable
class PlateManifest {
  const PlateManifest({
    required this.version,
    required this.atlases,
    required this.shelf,
    required this.hero,
    required this.plates,
  });

  static const String assetKey = 'assets/plates/manifest.json';

  /// Plate paths in the manifest are relative to this directory.
  static const String assetRoot = 'assets/plates/';

  factory PlateManifest.fromJson(Map<String, dynamic> j) {
    final atlases = <String, PlateAtlas>{};
    (j['atlas'] as Map<String, dynamic>? ?? const {}).forEach((k, v) {
      // Siblings such as `sleeve_mm` are not canvases.
      if (v is Map<String, dynamic> && v['canvas_mm'] is List) {
        atlases[k] = PlateAtlas.fromJson(k, v);
      }
    });
    final plates = <String, PlateSpec>{};
    (j['plates'] as Map<String, dynamic>).forEach((k, v) {
      plates[k] = PlateSpec.fromJson(k, v as Map<String, dynamic>);
    });
    final groups = j['groups'] as Map<String, dynamic>;
    return PlateManifest(
      version: (j['version'] as num?)?.toInt() ?? 1,
      atlases: Map.unmodifiable(atlases),
      shelf: ShelfGroup.fromJson(groups['shelf'] as Map<String, dynamic>),
      hero: HeroGroup.fromJson(
          groups['hero'] as Map<String, dynamic>, Map.unmodifiable(plates)),
      plates: Map.unmodifiable(plates),
    );
  }

  factory PlateManifest.parse(String text) =>
      PlateManifest.fromJson(jsonDecode(text) as Map<String, dynamic>);

  static final Expando<Future<PlateManifest>> _loaded = Expando();

  /// Loads (once per bundle) and parses the manifest asset.
  static Future<PlateManifest> load([AssetBundle? bundle]) {
    final b = bundle ?? rootBundle;
    return _loaded[b] ??= b
        .loadString(assetKey, cache: false)
        .then(PlateManifest.parse);
  }

  final int version;

  /// Label-artwork canvases by name (`hero`, `spine`, `tag`, …).
  final Map<String, PlateAtlas> atlases;
  final ShelfGroup shelf;
  final HeroGroup hero;

  /// Every plate, keyed like `shelf/tape_a` or `hero/rot_09`.
  final Map<String, PlateSpec> plates;

  PlateSpec plate(String key) {
    final p = plates[key];
    if (p == null) throw ArgumentError.value(key, 'key', 'no such plate');
    return p;
  }

  PlateSpec shelfPlate(String name) => plate('shelf/$name');
}

/// One artwork canvas (image space, y down).
@immutable
class PlateAtlas {
  const PlateAtlas({
    required this.name,
    required this.canvasMm,
    required this.regions,
  });

  factory PlateAtlas.fromJson(String name, Map<String, dynamic> j) {
    final c = (j['canvas_mm'] as List).cast<num>();
    final regions = <String, Rect>{};
    (j['regions'] as Map<String, dynamic>? ?? const {}).forEach((k, v) {
      final r = v as Map<String, dynamic>;
      regions[k] = Rect.fromLTWH(
        (r['x'] as num).toDouble(),
        (r['y'] as num).toDouble(),
        (r['w'] as num).toDouble(),
        (r['h'] as num).toDouble(),
      );
    });
    return PlateAtlas(
      name: name,
      canvasMm: Size(c[0].toDouble(), c[1].toDouble()),
      regions: Map.unmodifiable(regions),
    );
  }

  final String name;
  final Size canvasMm;

  /// Normalised x, y, w, h of each region.
  final Map<String, Rect> regions;

  /// Pixel size of this canvas painted at [pxPerMm].
  Size pixelSize(double pxPerMm) => Size(
      (canvasMm.width * pxPerMm).roundToDouble(),
      (canvasMm.height * pxPerMm).roundToDouble());
}

/// One rendered plate: where it sits in its group's frame and which images
/// carry it.
@immutable
class PlateSpec {
  const PlateSpec({
    required this.key,
    required this.name,
    required this.frame,
    required this.crop,
    required this.color,
    this.uv,
    this.uv2,
    this.atlas,
    this.tint = const [1, 1, 1],
    this.slot,
    this.extra = const {},
  });

  factory PlateSpec.fromJson(String key, Map<String, dynamic> j) {
    List<double> nums(Object? v) =>
        (v as List).cast<num>().map((e) => e.toDouble()).toList();
    final frame = nums(j['frame']);
    final crop = nums(j['crop']);
    const known = {
      'name', 'frame', 'crop', 'size', 'color', 'uv', 'uv2', 'atlas', //
      'uvset', 'tint', 'slot',
    };
    return PlateSpec(
      key: key,
      name: j['name'] as String? ?? key.split('/').last,
      frame: Size(frame[0], frame[1]),
      crop: Rect.fromLTWH(crop[0], crop[1], crop[2], crop[3]),
      color: j['color'] as String,
      uv: j['uv'] as String?,
      uv2: j['uv2'] as String?,
      atlas: (j['atlas'] ?? j['uvset']) as String?,
      tint: j['tint'] == null ? const [1, 1, 1] : nums(j['tint']),
      slot: (j['slot'] as num?)?.toInt(),
      extra: Map.unmodifiable({
        for (final e in j.entries)
          if (!known.contains(e.key)) e.key: e.value,
      }),
    );
  }

  /// Manifest key, e.g. `shelf/tape_a`.
  final String key;
  final String name;

  /// Full render frame of the group, px.
  final Size frame;

  /// Where this image sits inside [frame].
  final Rect crop;

  /// Image paths relative to [PlateManifest.assetRoot].
  final String color;
  final String? uv;
  final String? uv2;

  /// Which artwork canvas the UVs address (`spine`, `hero`, `tag`).
  final String? atlas;

  /// Colour of the label light.
  final List<double> tint;

  /// Shelf slot the plate was rendered in.
  final int? slot;

  /// Group-specific metadata (`pull_mm`, `lean_deg`, `index`, `progress`…).
  final Map<String, Object?> extra;

  /// Image size, px (== crop size).
  Size get size => crop.size;

  bool get hasLabel => uv != null && uv2 != null;

  /// Hero rotation frame index, when this is one.
  int? get index => (extra['index'] as num?)?.toInt();

  /// Cassette reel progress (0..1), when this is a cassette plate.
  double? get progress => (extra['progress'] as num?)?.toDouble();

  /// Supersampling factor relative to its group's frame (front_hi = 2).
  double get scale => (extra['scale'] as num?)?.toDouble() ?? 1;

  int get slotsUsed => (extra['slots_used'] as num?)?.toInt() ?? 1;

  List<String> get paths => [color, if (uv != null) uv!, if (uv2 != null) uv2!];

  @override
  String toString() => 'PlateSpec($key)';
}

/// `groups.shelf`: the bay geometry every shelf plate shares.
@immutable
class ShelfGroup {
  const ShelfGroup({
    required this.pxPerMm,
    required this.bayPx,
    required this.slots,
    required this.slotPx,
    required this.slot0LeftPx,
    required this.innerLeft,
    required this.innerRight,
    required this.plateSlot,
    required this.bays,
    required this.packed,
    required this.leanMaxTapes,
    required this.atlas,
  });

  factory ShelfGroup.fromJson(Map<String, dynamic> j) {
    final bay = (j['bay_px'] as List).cast<num>();
    final inner = (j['inner_px'] as List).cast<num>();
    return ShelfGroup(
      pxPerMm: (j['px_per_mm'] as num).toDouble(),
      bayPx: Size(bay[0].toDouble(), bay[1].toDouble()),
      slots: (j['slots'] as num).toInt(),
      slotPx: (j['slot_px'] as num).toDouble(),
      slot0LeftPx: (j['slot0_left_px'] as num).toDouble(),
      innerLeft: inner[0].toDouble(),
      innerRight: inner[1].toDouble(),
      plateSlot: (j['plate_slot'] as num).toInt(),
      bays: List.unmodifiable((j['bays'] as List).cast<String>()),
      packed: List.unmodifiable((j['packed'] as List).cast<String>()),
      leanMaxTapes: (j['lean_max_tapes'] as num).toInt(),
      atlas: j['atlas'] as String? ?? 'spine',
    );
  }

  final double pxPerMm;

  /// One bay (divider centre to divider centre) × one row band.
  final Size bayPx;
  final int slots;
  final double slotPx;
  final double slot0LeftPx;

  /// Between the dividers' inner faces.
  final double innerLeft;
  final double innerRight;
  final int plateSlot;
  final List<String> bays;
  final List<String> packed;
  final int leanMaxTapes;
  final String atlas;

  /// The inner clip as a rect over the full band height.
  Rect get innerRect =>
      Rect.fromLTRB(innerLeft, 0, innerRight, bayPx.height);
}

/// `groups.hero`: the rotation sequence, the hi-res front and the cassette.
@immutable
class HeroGroup {
  const HeroGroup({
    required this.frames,
    required this.stepDeg,
    required this.front,
    required this.size,
    required this.available,
    required this.floorCenterPx,
    required this.topCenterPx,
    required this.mmPerPxAtCenter,
    required this.atlas,
    required this.framePlates,
    required this.cassettePlates,
    this.frontHi,
  });

  factory HeroGroup.fromJson(
      Map<String, dynamic> j, Map<String, PlateSpec> plates) {
    final size = (j['size'] as List).cast<num>();
    final floor = (j['floor_center_px'] as List).cast<num>();
    final top = (j['top_center_px'] as List).cast<num>();
    final byIndex = <int, PlateSpec>{};
    final cassettes = <PlateSpec>[];
    PlateSpec? frontHi;
    for (final p in plates.values) {
      if (!p.key.startsWith('hero/')) continue;
      if (p.name.startsWith('rot_') && p.index != null) {
        byIndex[p.index!] = p;
      } else if (p.name.startsWith('cassette_') && p.progress != null) {
        cassettes.add(p);
      } else if (p.name == 'front_hi') {
        frontHi = p;
      }
    }
    cassettes.sort((a, b) => a.progress!.compareTo(b.progress!));
    // A frame is usable only when it is both listed and present.
    final listed = (j['available'] as List?)?.cast<num>().map((e) => e.toInt());
    final available = (listed ?? byIndex.keys)
        .where(byIndex.containsKey)
        .toSet()
        .toList()
      ..sort();
    return HeroGroup(
      frames: (j['frames'] as num).toInt(),
      stepDeg: (j['step_deg'] as num).toDouble(),
      front: (j['front'] as num).toInt(),
      size: Size(size[0].toDouble(), size[1].toDouble()),
      available: List.unmodifiable(available),
      floorCenterPx: Offset(floor[0].toDouble(), floor[1].toDouble()),
      topCenterPx: Offset(top[0].toDouble(), top[1].toDouble()),
      mmPerPxAtCenter: (j['mm_per_px_at_center'] as num?)?.toDouble() ?? 0.2671,
      atlas: j['atlas'] as String? ?? 'hero',
      framePlates: Map.unmodifiable(byIndex),
      cassettePlates: List.unmodifiable(cassettes),
      frontHi: frontHi,
    );
  }

  /// Frames in a full turn and the angle between them.
  final int frames;
  final double stepDeg;

  /// The frame that shows the front cover.
  final int front;
  final Size size;

  /// Frame indices present in this build, ascending.
  final List<int> available;
  final Offset floorCenterPx;
  final Offset topCenterPx;
  final double mmPerPxAtCenter;
  final String atlas;
  final Map<int, PlateSpec> framePlates;

  /// Ascending by progress.
  final List<PlateSpec> cassettePlates;
  final PlateSpec? frontHi;

  /// Signed shortest distance from [from] to [to] around the turn.
  int circularDelta(int from, int to) {
    var d = (to - from) % frames;
    if (d > frames ~/ 2) d -= frames;
    return d;
  }

  /// The available frame closest to [frame] (wrapping around the turn).
  int nearestAvailable(int frame) {
    if (available.isEmpty) return frame;
    final f = frame % frames;
    var best = available.first;
    var bestD = 1 << 30;
    for (final a in available) {
      final d = circularDelta(f, a).abs();
      if (d < bestD) {
        best = a;
        bestD = d;
      }
    }
    return best;
  }

  /// Available frames visited when turning from [from] to [to] the short
  /// way round, ending on the available frame nearest [to].
  List<int> path(int from, int to) {
    final end = nearestAvailable(to);
    final d = circularDelta(from, end);
    final step = d >= 0 ? 1 : -1;
    final out = <int>[];
    for (var i = 0; i.abs() <= d.abs(); i += step) {
      final f = (from + i) % frames;
      if (available.contains(f)) out.add(f);
    }
    if (out.isEmpty || out.last != end) out.add(end);
    return out;
  }

  /// The cassette plate whose reels best match [progress] (0..1).
  PlateSpec? cassetteFor(double progress) {
    PlateSpec? best;
    var bestD = double.infinity;
    for (final c in cassettePlates) {
      final d = (c.progress! - progress).abs();
      if (d < bestD) {
        best = c;
        bestD = d;
      }
    }
    return best;
  }

  /// Sleeve height in frame px (top centre to floor centre).
  double get sleeveHeightPx => floorCenterPx.dy - topCenterPx.dy;
}
