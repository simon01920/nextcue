import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import 'plates/plate_manifest.dart';

/// How a tape stands on the shelf.
enum TapePose {
  /// Packed upright (`tape_a..d`, picked per title).
  upright,

  /// Not started yet: still shrink-wrapped (`tape_sealed`).
  sealed,

  /// Being watched: pulled forward (`tape_pulled` + its shadow).
  pulled,
}

@immutable
class ShelfTape {
  const ShelfTape(this.titleId, [this.pose = TapePose.upright]);

  final String titleId;
  final TapePose pose;

  @override
  bool operator ==(Object other) =>
      other is ShelfTape && other.titleId == titleId && other.pose == pose;

  @override
  int get hashCode => Object.hash(titleId, pose);

  @override
  String toString() => 'ShelfTape($titleId, ${pose.name})';
}

/// A run of tapes under one rail card ("WATCHING · 7"). Every section
/// starts on a new bay.
@immutable
class ShelfSection {
  const ShelfSection({required this.label, required this.tapes});

  final String label;
  final List<ShelfTape> tapes;
}

/// One plate placed in a bay, in bay pixels (the shelf group's frame).
@immutable
class ShelfDraw {
  const ShelfDraw({
    required this.plate,
    required this.rect,
    this.tape,
    this.tag = false,
    this.clipInner = false,
  });

  /// Plate name in the shelf group (`bay_0`, `tape_c`, `rail`…).
  final String plate;

  /// Where the plate's whole image lands.
  final Rect rect;

  /// Index into [ShelfBay.tapes] whose spine art this plate carries.
  final int? tape;

  /// Carries the rail card art.
  final bool tag;

  /// Clipped to the bay's inner faces (`inner_px`).
  final bool clipInner;

  @override
  bool operator ==(Object other) =>
      other is ShelfDraw &&
      other.plate == plate &&
      other.rect == rect &&
      other.tape == tape &&
      other.tag == tag &&
      other.clipInner == clipInner;

  @override
  int get hashCode => Object.hash(plate, rect, tape, tag, clipInner);

  @override
  String toString() =>
      'ShelfDraw($plate @${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)}'
      '${tape == null ? '' : ' tape $tape'}${tag ? ' tag' : ''}${clipInner ? ' clip' : ''})';
}

/// One bay of one row band, ready to draw.
@immutable
class ShelfBay {
  const ShelfBay({
    required this.index,
    required this.section,
    required this.tag,
    required this.tapes,
    required this.slots,
    required this.draws,
    required this.tapeRects,
    required this.leans,
  });

  /// Position among all bays (also picks `bays[index % 3]`).
  final int index;

  /// Index of the section this bay belongs to.
  final int section;

  /// Rail card text.
  final String tag;
  final List<ShelfTape> tapes;

  /// First slot of each tape (the leaning tape covers two).
  final List<int> slots;

  /// In draw order (docs/PLATES.md, "Draw order per bay").
  final List<ShelfDraw> draws;

  /// Tap target of each tape, in bay pixels.
  final List<Rect> tapeRects;

  /// Whether the last tape leans on its neighbour.
  final bool leans;

  /// The draw that carries tape [i]'s spine (null when hidden).
  ShelfDraw? drawForTape(int i) {
    for (final d in draws) {
      if (d.tape == i) return d;
    }
    return null;
  }

  /// Identity of everything drawn: equal keys draw identical pixels for
  /// identical art.
  String get key => '$index|$tag|${draws.join(';')}|${tapes.map((t) => t.titleId).join(',')}';

  @override
  String toString() => 'ShelfBay($index, "$tag", ${tapes.length} tapes)';
}

/// Lays tapes out on bays exactly as `compose_bay` in
/// tools/plates/composite.py does. Pure and deterministic.
class ShelfLayout {
  ShelfLayout(this.group, this.plates);

  factory ShelfLayout.of(PlateManifest manifest) => ShelfLayout(
        manifest.shelf,
        {
          for (final p in manifest.plates.values)
            if (p.key.startsWith('shelf/')) p.name: p,
        },
      );

  final ShelfGroup group;

  /// Shelf plates by name.
  final Map<String, PlateSpec> plates;

  /// Rail card for the bay at [offset] tapes into a section of [total].
  static String tagFor(String label, int offset, int count, int total) {
    if (offset == 0) return '$label · $total';
    return '$label · ${offset + 1}–${offset + count} OF $total';
  }

  /// FNV-1a over UTF-16 code units, kept exact in 53-bit doubles (web).
  static int variantSeed(String titleId) {
    var h = 0x811c9dc5;
    for (final c in titleId.codeUnits) {
      h ^= c;
      // h * 0x01000193 mod 2^32, split so no product exceeds 2^42.
      h = (h * 0x193 + (h & 0xff) * 0x1000000) & 0xffffffff;
    }
    return h;
  }

  /// The packed variant (`tape_a..d`) a title always stands as.
  String packedFor(String titleId) =>
      group.packed[variantSeed(titleId) % group.packed.length];

  /// Every section split into bays of at most `slots` tapes; each section
  /// starts a new bay. Tapes in [hidden] keep their slot but are not drawn
  /// (the one lifted out for inspection).
  List<ShelfBay> layout(List<ShelfSection> sections,
      {Set<String> hidden = const {}}) {
    final bays = <ShelfBay>[];
    for (var s = 0; s < sections.length; s++) {
      final tapes = sections[s].tapes;
      if (tapes.isEmpty) continue;
      for (var start = 0; start < tapes.length; start += group.slots) {
        final end = (start + group.slots).clamp(0, tapes.length);
        bays.add(layoutBay(
          bays.length,
          tapes.sublist(start, end),
          tagFor(sections[s].label, start, end - start, tapes.length),
          section: s,
          hidden: hidden,
        ));
      }
    }
    return bays;
  }

  /// Number of bays [layout] produces, without building them.
  int bayCount(List<ShelfSection> sections) => sections.fold(
      0, (n, s) => n + (s.tapes.length + group.slots - 1) ~/ group.slots);

  ShelfBay layoutBay(int index, List<ShelfTape> tapes, String tag,
      {int section = 0, Set<String> hidden = const {}}) {
    assert(tapes.length <= group.slots);
    final draws = <ShelfDraw>[];

    void place(String name, int slot, {int? tape, bool clip = true}) {
      final p = plates[name]!;
      final dx = (slot - (p.slot ?? group.plateSlot)) * group.slotPx;
      draws.add(ShelfDraw(
        plate: name,
        rect: p.crop.shift(Offset(dx, 0)),
        tape: tape,
        clipInner: clip,
      ));
    }

    final bayPlate = group.bays[index % group.bays.length];
    draws.add(ShelfDraw(plate: bayPlate, rect: plates[bayPlate]!.crop));

    final k = tapes.length;
    final lean = k >= 2 && k <= group.leanMaxTapes;
    final uprights = lean ? k - 1 : k;
    bool shown(int i) => !hidden.contains(tapes[i].titleId);

    if (k > 0 && !lean && k < group.slots && shown(k - 1)) {
      place('tape_end_shadow', k - 1);
    }
    // One pulled tape per bay at most: a shelf where every watching tape
    // sticks out reads as a crooked row, not as "the one you're on".
    // Sections are ordered by last watched, so the first is the current one.
    final pulled = <int>[];
    for (var i = 0; i < uprights; i++) {
      final t = tapes[i];
      if (t.pose == TapePose.pulled && pulled.isEmpty) {
        pulled.add(i); // drawn after its neighbours
        continue;
      }
      if (!shown(i)) continue;
      place(t.pose == TapePose.sealed ? 'tape_sealed' : packedFor(t.titleId), i,
          tape: i);
    }
    for (final i in pulled) {
      if (!shown(i)) continue;
      place('tape_pulled_shadow', i);
      place('tape_pulled', i, tape: i);
    }
    if (lean && shown(k - 1)) place('tape_lean', uprights, tape: k - 1);

    final rail = plates['rail']!;
    draws.add(ShelfDraw(plate: 'rail', rect: rail.crop, tag: true));

    final railTop = rail.crop.top;
    final slots = <int>[for (var i = 0; i < k; i++) i];
    final rects = <Rect>[
      for (var i = 0; i < k; i++)
        Rect.fromLTWH(
          group.slot0LeftPx + i * group.slotPx,
          0,
          group.slotPx * (lean && i == k - 1 ? plates['tape_lean']!.slotsUsed : 1),
          railTop,
        ),
    ];
    return ShelfBay(
      index: index,
      section: section,
      tag: tag,
      tapes: List.unmodifiable(tapes),
      slots: List.unmodifiable(slots),
      draws: List.unmodifiable(draws),
      tapeRects: List.unmodifiable(rects),
      leans: lean,
    );
  }

  /// The bay frame size, px.
  Size get bayPx => group.bayPx;
}
