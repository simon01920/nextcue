import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/shelf/plates/plate_manifest.dart';
import 'package:showtrack/shelf/shelf_layout.dart';

void main() {
  final manifest =
      PlateManifest.parse(File('assets/plates/manifest.json').readAsStringSync());
  final layout = ShelfLayout.of(manifest);
  final g = manifest.shelf;

  List<ShelfTape> tapes(int n, {TapePose Function(int i)? pose}) => [
        for (var i = 0; i < n; i++)
          ShelfTape('series-$i', pose?.call(i) ?? TapePose.upright),
      ];

  List<ShelfBay> lay(int n, {TapePose Function(int i)? pose}) => layout
      .layout([ShelfSection(label: 'DRAMA', tapes: tapes(n, pose: pose))]);

  List<String> names(ShelfBay b) => [for (final d in b.draws) d.plate];

  /// Plate position as compose_bay places it.
  Rect at(String plate, int slot) {
    final p = manifest.shelfPlate(plate);
    return p.crop.shift(ui(slot - p.slot!) * g.slotPx);
  }

  group('manifest', () {
    test('reads the shelf group and plates', () {
      expect(manifest.version, 2);
      expect(g.bayPx.width, 1116);
      expect(g.slots, 12);
      expect(g.slotPx, 86);
      expect(g.packed, ['tape_a', 'tape_b', 'tape_c', 'tape_d']);
      expect(manifest.shelfPlate('rail').atlas, 'tag');
      expect(manifest.atlases['tag']!.regions.keys, contains('card'));
      expect(manifest.shelfPlate('tape_a').hasLabel, isTrue);
      expect(manifest.shelfPlate('bay_0').hasLabel, isFalse);
    });

    test('reads the hero group without hard-coded counts', () {
      final h = manifest.hero;
      expect(h.framePlates.length, h.available.length);
      expect(h.available, everyElement(lessThan(h.frames)));
      expect(h.front, lessThan(h.frames));
      expect(h.frontHi, isNotNull);
      expect(h.cassettePlates.map((c) => c.progress),
          orderedEquals([0.0, 0.25, 0.5, 0.75, 1.0]));
      expect(h.cassetteFor(0.4)!.progress, 0.5);
      expect(h.cassetteFor(0.1)!.progress, 0.0);
      // The intro turns from the spine to the front through every
      // available frame, the short way round.
      final path = h.path(0, h.front);
      expect(path.first, h.nearestAvailable(0));
      expect(path.last, h.front);
      expect(path, orderedEquals([...path]..sort()));
      expect(h.circularDelta(h.frames - 1, 1), 2);
      expect(h.circularDelta(1, h.frames - 1), -2);
    });
  });

  group('draw order (compose_bay)', () {
    test('1 tape: bay, end shadow, tape, rail', () {
      final bays = lay(1);
      expect(bays, hasLength(1));
      final b = bays.single;
      expect(names(b), ['bay_0', 'tape_end_shadow', layout.packedFor('series-0'), 'rail']);
      expect(b.leans, isFalse);
      expect(b.draws[1].rect, at('tape_end_shadow', 0));
      expect(b.draws[1].clipInner, isTrue);
      expect(b.draws[2].tape, 0);
      expect(b.draws.last.tag, isTrue);
      expect(b.tag, 'DRAMA · 1');
    });

    test('2 tapes: the last leans on its neighbour, no end shadow', () {
      final b = lay(2).single;
      expect(names(b), ['bay_0', layout.packedFor('series-0'), 'tape_lean', 'rail']);
      expect(b.leans, isTrue);
      expect(b.draws[2].rect, at('tape_lean', 1));
      expect(b.draws[2].tape, 1);
      expect(b.draws[2].clipInner, isTrue);
      expect(b.tapeRects[1].width, g.slotPx * 2);
    });

    test('11 tapes: 10 upright, the 11th leans in slots 10-11', () {
      final b = lay(11).single;
      expect(b.leans, isTrue);
      expect(names(b).where((n) => n == 'tape_lean'), hasLength(1));
      expect(b.draws.firstWhere((d) => d.plate == 'tape_lean').rect,
          at('tape_lean', 10));
      expect(names(b), isNot(contains('tape_end_shadow')));
      expect(names(b).length, 1 + 10 + 1 + 1);
    });

    test('12 tapes: full bay, no shadow, no lean', () {
      final b = lay(12).single;
      expect(b.leans, isFalse);
      expect(names(b), isNot(contains('tape_end_shadow')));
      expect(names(b), isNot(contains('tape_lean')));
      for (var i = 0; i < 12; i++) {
        final d = b.drawForTape(i)!;
        expect(d.rect, at(d.plate, i), reason: 'tape $i');
      }
    });

    test('13 tapes: a full bay and a bay of one', () {
      final bays = lay(13);
      expect(bays, hasLength(2));
      expect(bays[0].tapes, hasLength(12));
      expect(bays[1].tapes, hasLength(1));
      expect(names(bays[1]), contains('tape_end_shadow'));
      expect(names(bays[1]).first, 'bay_1');
      expect(bays[0].tag, 'DRAMA · 13');
      expect(bays[1].tag, 'DRAMA · 13–13 OF 13');
    });

    test('100 tapes: 8 full bays and one of 4 (leaning)', () {
      final bays = lay(100);
      expect(bays, hasLength(9));
      expect(bays.take(8).every((b) => b.tapes.length == 12), isTrue);
      expect(bays.last.tapes, hasLength(4));
      expect(bays.last.leans, isTrue);
      expect([for (final b in bays) b.draws.first.plate],
          ['bay_0', 'bay_1', 'bay_2', 'bay_0', 'bay_1', 'bay_2', 'bay_0', 'bay_1', 'bay_2']);
      expect(layout.bayCount([ShelfSection(label: 'X', tapes: tapes(100))]), 9);
    });

    test('500 tapes: 41 full bays and one of 8; every tape drawn once', () {
      final bays = lay(500);
      expect(bays, hasLength(42));
      expect(bays.last.tapes, hasLength(8));
      final drawn = <String>[
        for (final b in bays)
          for (final d in b.draws)
            if (d.tape != null) b.tapes[d.tape!].titleId,
      ];
      expect(drawn, hasLength(500));
      expect(drawn.toSet(), hasLength(500));
      expect([for (final b in bays) b.index], List.generate(42, (i) => i));
    });

    test('sealed tapes use tape_sealed; one pulled tape per bay, drawn last',
        () {
      final b = lay(12, pose: (i) => switch (i) {
            2 || 7 => TapePose.pulled,
            4 => TapePose.sealed,
            _ => TapePose.upright,
          }).single;
      final n = names(b);
      expect(b.drawForTape(4)!.plate, 'tape_sealed');
      // Only the first watching tape (the most recently watched) sticks out;
      // the second stands packed with the uprights.
      expect(b.drawForTape(7)!.plate, startsWith('tape_'));
      expect(b.drawForTape(7)!.plate, isNot('tape_pulled'));
      final pulledAt = n.indexOf('tape_pulled_shadow');
      expect(pulledAt, 1 + 11);
      expect(n.sublist(pulledAt, pulledAt + 2), ['tape_pulled_shadow', 'tape_pulled']);
      expect(n.where((x) => x == 'tape_pulled'), hasLength(1));
      expect(b.draws[pulledAt].rect, at('tape_pulled_shadow', 2));
      expect(b.draws[pulledAt + 1].tape, 2);
      expect(n.last, 'rail');
    });

    test('a pulled last tape still leans when the bay leans', () {
      final b = lay(5, pose: (i) => TapePose.pulled).single;
      expect(b.leans, isTrue);
      expect(names(b).where((x) => x == 'tape_pulled'), hasLength(1));
      expect(b.drawForTape(4)!.plate, 'tape_lean');
    });

    test('sections start new bays and label their rail cards', () {
      final bays = layout.layout([
        ShelfSection(label: 'WATCHING', tapes: tapes(7)),
        const ShelfSection(label: 'EMPTY', tapes: []),
        ShelfSection(label: 'COMPLETED', tapes: [
          for (var i = 0; i < 14; i++) ShelfTape('movie-$i'),
        ]),
      ]);
      expect(bays.map((b) => b.tag),
          ['WATCHING · 7', 'COMPLETED · 14', 'COMPLETED · 13–14 OF 14']);
      expect(bays.map((b) => b.section), [0, 2, 2]);
      expect(bays.map((b) => b.tapes.length), [7, 12, 2]);
    });

    test('hidden tapes keep their slot but are not drawn', () {
      final b = layout.layout(
          [ShelfSection(label: 'X', tapes: tapes(6))],
          hidden: {'series-2'}).single;
      expect(b.drawForTape(2), isNull);
      expect(b.drawForTape(3)!.rect, at(b.drawForTape(3)!.plate, 3));
    });
  });

  group('determinism', () {
    test('same input, same layout', () {
      final a = lay(37, pose: (i) => TapePose.values[i % 3]);
      final b = lay(37, pose: (i) => TapePose.values[i % 3]);
      expect([for (final x in a) x.key], [for (final x in b) x.key]);
      expect([for (final x in a) x.draws], [for (final x in b) x.draws]);
    });

    test('the packed variant is a stable function of the title id', () {
      // FNV-1a reference values.
      expect(ShelfLayout.variantSeed(''), 0x811c9dc5);
      expect(ShelfLayout.variantSeed('a'), 0xe40c292c);
      expect(ShelfLayout.variantSeed('foobar'), 0xbf9cf968);
      final variants = {
        for (var i = 0; i < 200; i++) layout.packedFor('series-$i'),
      };
      expect(variants, g.packed.toSet(), reason: 'all four variants in use');
      // Moving a tape does not change its variant.
      final a = lay(12).single, b = layout.layout([
        ShelfSection(label: 'DRAMA', tapes: tapes(12).reversed.toList()),
      ]).single;
      expect(b.drawForTape(11)!.plate, a.drawForTape(0)!.plate);
    });
  });
}

/// Horizontal offset helper.
Offset ui(int slots) => Offset(slots.toDouble(), 0);
