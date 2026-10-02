import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/shelf/labels/atlas_layout.dart';
import 'package:showtrack/shelf/labels/label_composer.dart';
import 'package:showtrack/shelf/labels/label_palette.dart';
import 'package:showtrack/shelf/labels/label_rng.dart';
import 'package:showtrack/shelf/labels/spine_style.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';

import 'label_test_utils.dart';

/// 30 realistic ids: TVDB-style series/movie ids and AniList fallbacks.
final ids = <String>[
  for (var i = 0; i < 12; i++) 'series-${81189 + i * 7919}',
  for (var i = 0; i < 10; i++) 'movie-${120 + i * 4651}',
  for (var i = 0; i < 8; i++) 'series-al-${21000 + i * 313}',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rng is stable across platforms', () {
    test('32-bit multiply matches Math.imul', () {
      expect(imul32(0xFFFFFFFF, 5), 0xFFFFFFFB);
      expect(imul32(0x7FFFFFFF, 0x7FFFFFFF), 1);
      expect(imul32(123456789, 987654321), 4227814277);
    });

    test('hash and sequence are pinned (VM == dart2js, verified)', () {
      expect(hashString('series-81189'), 2320245185);
      expect(hashString(''), 2872998923);
      final r = LabelRng(hashString('series-81189'));
      expect([r.nextUint32(), r.nextUint32(), r.nextUint32()],
          [315378724, 2009354719, 2487574105]);
    });
  });

  group('style determinism', () {
    test('same titleId → identical style', () {
      for (final id in ids) {
        final a = LabelComposer.styleFor(id), b = SpineStyleSpec.forTitle(id);
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      }
    });

    test('30 ids → varied styles (≥ 6 kinds, varied sub-styles)', () {
      final specs = ids.map(SpineStyleSpec.forTitle).toList();
      final kinds = specs.map((s) => s.kind).toSet();
      final combos = specs.map((s) => '${s.kind.name}/${s.variant}').toSet();
      final marks = specs.map((s) => '${s.markAtTop}/${s.markStyle}').toSet();
      final catalogues = specs.map((s) => s.catalogue).toSet();
      final wear = specs.map((s) => s.wear).toList()..sort();
      debugPrint('kinds used: ${kinds.map((k) => k.name).toList()} '
          '(${combos.length} kind/variant combos)');
      expect(kinds.length, greaterThanOrEqualTo(6));
      expect(combos.length, greaterThanOrEqualTo(14));
      expect(marks.length, greaterThanOrEqualTo(4));
      expect(catalogues.length, greaterThanOrEqualTo(28));
      expect(wear.last - wear.first, greaterThan(0.3));
    });

    test('a composed atlas is pixel-identical for the same input', () async {
      await loadLabelFonts();
      final poster = await posterRing();
      final d = TapeLabelData(
        titleId: 'movie-pan-6',
        title: 'Pán prsteňov: Spoločenstvo prsteňa',
        year: '2001',
        isMovie: true,
        poster: poster,
        state: const TapeState.notStarted(),
      );
      final c = LabelComposer();
      final a = await c.composeShelf(d, widthPx: 160);
      final b = await LabelComposer().composeShelf(d, widthPx: 160);
      final ba = await a.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bb = await b.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(ba!.buffer.asUint8List(), bb!.buffer.asUint8List());
    });

    test('palette: sampled once per poster, deterministic, curated without', () async {
      final poster = await posterRose();
      final p1 = await TapePalette.resolve('x', poster);
      final p2 = await TapePalette.resolve('x', poster);
      expect(p1, p2);
      expect(p1.fromPoster, isTrue);
      // The rose poster is pink/red: the lead colour must be in that family.
      final hue = HSLColor.fromColor(p1.accent).hue;
      expect(hue > 300 || hue < 20, isTrue, reason: 'accent hue $hue');
      final none = await TapePalette.resolve('series-lost-2', null);
      expect(none.fromPoster, isFalse);
      expect(TapePalette.curated, contains(none));
    });
  });

  group('atlas manifest', () {
    test('embedded copy matches assets/plates/manifest.json', () {
      final fromDisk =
          AtlasManifest.parse(File('assets/plates/manifest.json').readAsStringSync());
      // The composer's contract: hero + spine layouts and the sleeve size.
      // (The plate pipeline may add other layouts, e.g. "tag", "dvd".)
      expect(fromDisk.hero, AtlasManifest.standard.hero);
      expect(fromDisk.spine, AtlasManifest.standard.spine);
      expect(fromDisk.sleeveMm, AtlasManifest.standard.sleeveMm);
      expect(fromDisk.version, greaterThanOrEqualTo(2));
    });

    test('v1 manifests (layouts at the top level) still parse', () {
      const v1 = '{"version": 1, "sleeve_mm": [107.0, 190.5, 28.0], '
          '"hero": {"canvas_mm": [256.0, 256.0], "regions": {"front": '
          '{"x": 0.52734375, "y": 0.0, "w": 0.41796875, "h": 0.744140625, "mm": [107.0, 190.5]}}}, '
          '"spine": {"canvas_mm": [48.0, 190.5], "regions": {"spine": '
          '{"x": 0.0, "y": 0.0, "w": 0.5833333333333334, "h": 1.0, "mm": [28.0, 190.5]}}}}';
      final m = AtlasManifest.parse(v1);
      expect(m.version, 1);
      expect(m.hero.region('front'), AtlasManifest.standard.hero.region('front'));
      expect(m.spine.region('spine'), AtlasManifest.standard.spine.region('spine'));
      expect(() => AtlasManifest.parse('{"version": 3}'), throwsFormatException);
    });

    test('regions in design units and pixels', () {
      final m = AtlasManifest.standard;
      expect(m.spine.pixelSizeForWidth(224), const Size(224, 889));
      expect(m.spine.designRect('spine'), const Rect.fromLTWH(0, 0, 280, 1905));
      expect(m.spine.designRect('front_strip').left, closeTo(280, 1e-9));
      expect(m.hero.designRect('front').left, closeTo(1350, 1e-9));
      expect(m.hero.designRect('front').width, closeTo(1070, 1e-9));
      expect(m.hero.pixelRect('cassette_spine', const Size(1024, 1024)).width,
          closeTo(588, 1e-9));
      expect(() => m.hero.region('nope'), throwsArgumentError);
    });
  });

  test('TapeLabelData equality and cache key', () async {
    final img = await posterSnow();
    TapeLabelData make({ui.Image? poster, TapeState st = const TapeState.notStarted()}) =>
        TapeLabelData(titleId: 'a', title: 'Tři oříšky', poster: poster, state: st);
    expect(make(poster: img), make(poster: img));
    expect(make(poster: img).cacheKey, make(poster: img).cacheKey);
    expect(make(poster: img) == make(), isFalse);
    expect(make().cacheKey == make(st: const TapeState.completed()).cacheKey, isFalse);
  });
}
