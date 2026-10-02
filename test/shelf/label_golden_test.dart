import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/shelf/labels/atlas_layout.dart';
import 'package:showtrack/shelf/labels/label_composer.dart';
import 'package:showtrack/shelf/labels/label_text.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';
import 'package:showtrack/shelf/labels/title_fitter.dart';

import 'label_test_utils.dart';

late List<TapeLabelData> tapes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadLabelFonts();
    tapes = await SampleTapes.all();
  });

  final manifest = AtlasManifest.standard;

  void expectInsideRegions(List<TextPlacement> placements, AtlasLayout layout,
      Size px, String what) {
    expect(placements, isNotEmpty, reason: what);
    for (final p in placements) {
      final region = layout.pixelRect(p.region, px).inflate(0.75);
      final inside = region.contains(p.rect.topLeft) &&
          region.contains(p.rect.bottomRight - const Offset(0.001, 0.001));
      expect(inside, isTrue,
          reason: '$what: "${p.text}" ${p.rect} leaves ${p.region} $region');
    }
  }

  test('golden: a shelf row of composed spines', () async {
    final composer = LabelComposer(recordText: true);
    final atlases = <ui.Image>[];
    final photos = await PhotoTapes.all();
    // Eight real titles (posters, one clear logo, two without any art) plus
    // two with full photographic TVDB-style artwork (logo on the spine).
    for (final t in [...tapes, photos['full_art']!, photos['no_poster']!]) {
      final img = await composer.composeShelf(t, widthPx: 224);
      expectInsideRegions(composer.lastTextPlacements, manifest.spine,
          Size(img.width.toDouble(), img.height.toDouble()), t.title);
      atlases.add(img);
    }
    final row = await _shelfRow(atlases);
    await expectLater(row, matchesGoldenFile('goldens/shelf_row.png'));
  });

  test('golden: hero atlas (poster)', () async {
    final composer = LabelComposer(recordText: true);
    final img = await composer.composeHero(tapes[1], sizePx: 1024);
    expectInsideRegions(composer.lastTextPlacements, manifest.hero,
        const Size(1024, 1024), tapes[1].title);
    await expectLater(img, matchesGoldenFile('goldens/hero_atlas.png'));
  });

  test('golden: hero atlas (no poster, typographic fallback)', () async {
    final composer = LabelComposer(recordText: true);
    final img = await composer.composeHero(tapes[3], sizePx: 1024);
    expectInsideRegions(composer.lastTextPlacements, manifest.hero,
        const Size(1024, 1024), tapes[3].title);
    await expectLater(img, matchesGoldenFile('goldens/hero_atlas_no_poster.png'));
  });

  test('golden: hero atlas (photographic artwork: poster, logo, banner, background)',
      () async {
    final composer = LabelComposer(recordText: true);
    final t = (await PhotoTapes.all())['full_art']!;
    final img = await composer.composeHero(t, sizePx: 1024);
    expectInsideRegions(composer.lastTextPlacements, manifest.hero,
        const Size(1024, 1024), t.title);
    await expectLater(img, matchesGoldenFile('goldens/hero_atlas_photo.png'));
  });

  test('no text leaves its region, for every sample in both atlases', () async {
    final composer = LabelComposer(recordText: true);
    for (final t in [...tapes, ...(await PhotoTapes.all()).values]) {
      await composer.composeHero(t, sizePx: 768);
      expectInsideRegions(composer.lastTextPlacements, manifest.hero,
          const Size(768, 768), 'hero ${t.title}');
      final s = await composer.composeShelf(t, widthPx: 192);
      expectInsideRegions(composer.lastTextPlacements, manifest.spine,
          Size(s.width.toDouble(), s.height.toDouble()), 'shelf ${t.title}');
    }
  });

  test('atlases are opaque inside every region, composed back to back', () async {
    // Regression: shared Paint state once leaked alpha from one tape's
    // print into the next tape's gradient fills.
    final composer = LabelComposer();
    for (final t in [...tapes, ...tapes.reversed]) {
      await _expectOpaque(await composer.composeHero(t, sizePx: 512), manifest.hero,
          'hero ${t.title}');
      await _expectOpaque(await composer.composeShelf(t, widthPx: 224), manifest.spine,
          'shelf ${t.title}');
    }
  });

  test('shelf spine and front strip are the hero spine and front, pixel for pixel',
      () async {
    // 192 px shelf and 1024 px hero are both exactly 4 px/mm.
    final composer = LabelComposer();
    for (final t in [tapes[0], tapes[3], tapes[5]]) {
      final shelf = await composer.composeShelf(t, widthPx: 192);
      final hero = await composer.composeHero(t, sizePx: 1024);
      final sPx = Size(shelf.width.toDouble(), shelf.height.toDouble());
      const hPx = Size(1024, 1024);
      final spineDiff = await _meanDiff(shelf, manifest.spine.pixelRect('spine', sPx),
          hero, manifest.hero.pixelRect('spine', hPx));
      final strip = manifest.spine.pixelRect('front_strip', sPx);
      final front = manifest.hero.pixelRect('front', hPx);
      final stripDiff = await _meanDiff(shelf, strip, hero,
          Rect.fromLTWH(front.left, front.top, strip.width, strip.height));
      debugPrint('${t.title}: spine Δ ${spineDiff.toStringAsFixed(3)}, '
          'front strip Δ ${stripDiff.toStringAsFixed(3)} (mean /255)');
      expect(spineDiff, lessThan(1.0));
      expect(stripDiff, lessThan(1.0));
    }
  });

  test('compose timings', () async {
    final composer = LabelComposer();
    // Cold: empty text caches and a poster the palette sampler hasn't seen.
    TitleFitter.clearCaches();
    LabelText.clearCache();
    final cold = tapes[2].copyWith(poster: await posterRing());
    final swCold = Stopwatch()..start();
    (await composer.composeShelf(cold)).dispose();
    final coldShelf = swCold.elapsedMicroseconds / 1000;
    swCold
      ..reset()
      ..start();
    (await composer.composeHero(cold)).dispose();
    final coldHero = swCold.elapsedMicroseconds / 1000;
    debugPrint('cold compose (first time for a title/poster): '
        'shelf ${coldShelf.toStringAsFixed(1)} ms, hero ${coldHero.toStringAsFixed(1)} ms');
    // Warm up caches (fonts, grain tile, palettes).
    for (final t in tapes) {
      await composer.composeShelf(t);
      await composer.composeHero(t);
    }
    final sw = Stopwatch();
    const rounds = 3;
    var shelfMs = 0.0, heroMs = 0.0, shelfRecMs = 0.0, heroRecMs = 0.0;
    for (var r = 0; r < rounds; r++) {
      for (final t in tapes) {
        sw
          ..reset()
          ..start();
        (await composer.composeShelf(t)).dispose();
        shelfMs += sw.elapsedMicroseconds / 1000;
        sw
          ..reset()
          ..start();
        (await composer.composeHero(t)).dispose();
        heroMs += sw.elapsedMicroseconds / 1000;
      }
    }
    // Recording only (the CPU work on the UI isolate; rasterisation runs
    // on the raster thread / GPU on device).
    final ctxComposer = LabelComposer();
    for (final t in tapes) {
      final ctx = await ctxComposer.debugContext(t);
      sw
        ..reset()
        ..start();
      ctxComposer.recordShelf(ctx, const Size(224, 889)).dispose();
      shelfRecMs += sw.elapsedMicroseconds / 1000;
      sw
        ..reset()
        ..start();
      ctxComposer.recordHero(ctx, const Size(1536, 1536)).dispose();
      heroRecMs += sw.elapsedMicroseconds / 1000;
    }
    final n = rounds * tapes.length;
    debugPrint('compose timings (flutter_tester, software raster): '
        'shelf 224 px ${(shelfMs / n).toStringAsFixed(1)} ms, '
        'hero 1536 px ${(heroMs / n).toStringAsFixed(1)} ms; '
        'recording only: shelf ${(shelfRecMs / tapes.length).toStringAsFixed(2)} ms, '
        'hero ${(heroRecMs / tapes.length).toStringAsFixed(2)} ms');
    // Loose ceilings — only to catch pathological regressions in CI.
    expect(shelfMs / n, lessThan(500));
    expect(heroMs / n, lessThan(3000));
  });
}

Future<double> _meanDiff(ui.Image a, Rect ra, ui.Image b, Rect rb) async {
  final da = (await a.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final db = (await b.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final w = ra.width.round(), h = ra.height.round();
  var sum = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final ia = ((ra.top.round() + y) * a.width + ra.left.round() + x) * 4;
      final ib = ((rb.top.round() + y) * b.width + rb.left.round() + x) * 4;
      for (var c = 0; c < 3; c++) {
        sum += (da[ia + c] - db[ib + c]).abs();
      }
    }
  }
  return sum / (w * h * 3);
}

Future<ui.Image> _shelfRow(List<ui.Image> atlases) async {
  final layout = AtlasManifest.standard.spine;
  final a0 = atlases.first;
  final size = Size(a0.width.toDouble(), a0.height.toDouble());
  final spine = layout.pixelRect('spine', size);
  const gap = 8.0, pad = 16.0;
  final w = pad * 2 + atlases.length * spine.width + (atlases.length - 1) * gap;
  final h = spine.height + pad * 2;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF141416));
  for (var i = 0; i < atlases.length; i++) {
    final x = pad + i * (spine.width + gap);
    c.drawImageRect(atlases[i], spine, Rect.fromLTWH(x, pad, spine.width, spine.height),
        Paint()..filterQuality = FilterQuality.none);
  }
  final pic = rec.endRecording();
  return pic.toImage(w.round(), h.round());
}

Future<void> _expectOpaque(ui.Image img, AtlasLayout layout, String what) async {
  final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final size = Size(img.width.toDouble(), img.height.toDouble());
  for (final region in layout.regions.values) {
    final r = region.rectIn(size);
    for (var y = r.top.ceil(); y < r.bottom.floor(); y += 3) {
      for (var x = r.left.ceil(); x < r.right.floor(); x += 3) {
        final a = d[(y * img.width + x) * 4 + 3];
        if (a != 255) {
          fail('$what: ${region.name} pixel ($x, $y) has alpha $a');
        }
      }
    }
  }
}