// The fragment shader and the CPU fallback implement the same maths
// (docs/PLATES.md, tools/plates/composite.py); compare them pixel by pixel
// on real plates, at 1 : 1 and magnified.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';
import 'package:showtrack/shelf/plates/plate_cache.dart';
import 'package:showtrack/shelf/plates/plate_compositor.dart';
import 'package:showtrack/shelf/plates/plate_manifest.dart';

import 'shelf_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlateManifest manifest;
  late PlateImageCache cache;
  late PlateCompositor gpu;
  final cpu = PlateCompositor(null);

  setUpAll(() async {
    await loadShelfFonts();
    manifest = await PlateManifest.load();
    cache = PlateImageCache(budgetBytes: 64 << 20);
    gpu = await PlateCompositor.create();
  });

  test('the plate shader compiles and loads under flutter test', () {
    expect(gpu.usesShader, isTrue);
  });

  Future<RgbaPixels> render(PlateCompositor c, PlateImages p, ui.Image art,
          Size size) async =>
      RgbaPixels.of(await c.renderPlate(p, art, size));

  /// Fraction of pixels whose channels all agree within [tol].
  double agreement(RgbaPixels a, RgbaPixels b, {int tol = 3}) {
    expect(a.width, b.width);
    expect(a.height, b.height);
    var ok = 0;
    final n = a.width * a.height;
    for (var i = 0; i < n; i++) {
      var same = true;
      for (var k = 0; k < 4; k++) {
        if ((a.data[i * 4 + k] - b.data[i * 4 + k]).abs() > tol) {
          same = false;
          break;
        }
      }
      if (same) ok++;
    }
    return ok / n;
  }

  for (final scale in [1.0, 1.7]) {
    test('shelf tape: shader == CPU at ${scale}x', () async {
      final spec = manifest.shelfPlate('tape_b');
      final p = await cache.acquirePlate(spec);
      final art = await fixtureSpineArt(
          const TapeLabelData(
              titleId: 'series-81189',
              title: 'Breaking Bad',
              state: TapeState(kind: TapeStateKind.completed)),
          (144 * scale).round());
      final size = Size((spec.size.width * scale).roundToDouble(),
          (spec.size.height * scale).roundToDouble());
      final a = await render(gpu, p, art, size);
      final b = await render(cpu, p, art, size);
      expect(agreement(a, b), greaterThan(0.995));
      // And the label really is there: the art changes the pixels.
      final bare = await RgbaPixels.of(await gpu.render(
          size.width.round(), size.height.round(), [
        PlateDraw(images: p, dst: Offset.zero & size),
      ]));
      expect(agreement(a, bare), lessThan(0.9));
      p.dispose();
      art.dispose();
    });
  }

  test('hero front frame (13-bit UVs): shader == CPU', () async {
    final h = manifest.hero;
    final spec = h.framePlates[h.front]!;
    final p = await cache.acquirePlate(spec);
    // A hero atlas stand-in: four colour fields over the regions.
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const n = 512.0;
    final atlas = manifest.atlases['hero']!;
    final colors = [
      const Color(0xFFD9342B), const Color(0xFF1F6FB2), const Color(0xFFF2C14E),
      const Color(0xFF2E8B57), const Color(0xFF7B3FA0),
    ];
    var i = 0;
    for (final r in atlas.regions.values) {
      c.drawRect(Rect.fromLTWH(r.left * n, r.top * n, r.width * n, r.height * n),
          Paint()..color = colors[i++ % colors.length]);
    }
    final art = await rec.endRecording().toImage(n.toInt(), n.toInt());
    const size = Size(320, 450);
    final a = await render(gpu, p, art, size);
    final b = await render(cpu, p, art, size);
    expect(agreement(a, b, tol: 4), greaterThan(0.99));
    p.dispose();
    art.dispose();
  });
}
