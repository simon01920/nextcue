import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'label_palette.dart';
import 'label_rng.dart';
import 'label_text.dart';

/// Print-process helpers: grain, poster grading, vignette and the small
/// recurring print marks (studio mark, VHS logo). All sizes in design
/// units (0.1 mm).
class LabelPrint {
  LabelPrint._();

  static Future<ui.Image>? _grain;

  /// A 128² tile of neutral (50 % grey) film/print grain, generated once
  /// per process by scattering points — no per-pixel loops.
  static Future<ui.Image> grainTile() => _grain ??= _makeGrain();

  static Future<ui.Image> _makeGrain() async {
    const n = 128;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, n * 1.0, n * 1.0),
        Paint()..color = const Color(0xFF808080));
    final rng = LabelRng(0x5EED);
    const levels = 10;
    final pts = List<List<double>>.generate(levels, (_) => <double>[]);
    for (var i = 0; i < 11000; i++) {
      // Triangular distribution around mid grey.
      final v = (rng.nextDouble() + rng.nextDouble()) / 2;
      final k = (v * levels).floor().clamp(0, levels - 1);
      pts[k]
        ..add(rng.nextInt(n) + 0.5)
        ..add(rng.nextInt(n) + 0.5);
    }
    final p = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    for (var k = 0; k < levels; k++) {
      final g = (40 + (k + 0.5) / levels * 175).round();
      p.color = Color.fromARGB(255, g, g, g);
      c.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts[k]), p);
    }
    final pic = rec.endRecording();
    final img = await pic.toImage(n, n);
    pic.dispose();
    return img;
  }

  static Future<ui.Image>? _speckle;

  /// A 128² transparent tile of scattered opaque specks — an alpha mask
  /// for ink that didn't take (rubber stamps, worn print).
  static Future<ui.Image> speckleTile() => _speckle ??= _makeSpeckle();

  static Future<ui.Image> _makeSpeckle() async {
    const n = 128;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final rng = LabelRng(0xD07);
    final p = Paint()..strokeCap = StrokeCap.round;
    for (var level = 0; level < 4; level++) {
      final pts = <double>[];
      for (var i = 0; i < 260; i++) {
        pts
          ..add(rng.nextDouble() * n)
          ..add(rng.nextDouble() * n);
      }
      p
        ..color = Color.fromRGBO(255, 255, 255, 0.35 + level * 0.2)
        ..strokeWidth = 1.0 + level * 0.9;
      c.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts), p);
    }
    final pic = rec.endRecording();
    final img = await pic.toImage(n, n);
    pic.dispose();
    return img;
  }

  /// Overlays grain on [rect]. [texel] is the grain size in design units.
  static void grain(Canvas canvas, Rect rect, ui.Image tile,
      {double opacity = 0.16, double texel = 1.8, BlendMode mode = BlendMode.overlay}) {
    final m = Float64List.fromList(<double>[
      texel, 0, 0, 0, //
      0, texel, 0, 0, //
      0, 0, 1, 0, //
      rect.left, rect.top, 0, 1, //
    ]);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ImageShader(tile, TileMode.repeated, TileMode.repeated, m,
            filterQuality: FilterQuality.low)
        ..blendMode = mode
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
  }

  /// Print grade, part 1 (linear): slightly muted, warm, blacks lifted and
  /// whites held — ink on board never reaches #000/#FFF. The gentle
  /// contrast S-curve is part 2: the poster soft-lit onto itself (see
  /// [cover]).
  static final ColorFilter posterGrade = ColorFilter.matrix(_gradeMatrix());

  static List<double> _gradeMatrix() {
    const s = 0.9; // saturation
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sat = <double>[
      lr * (1 - s) + s, lg * (1 - s), lb * (1 - s),
      lr * (1 - s), lg * (1 - s) + s, lb * (1 - s),
      lr * (1 - s), lg * (1 - s), lb * (1 - s) + s,
    ];
    const lo = 0.045, hi = 0.955; // printable range
    const warm = [1.03, 1.0, 0.935];
    const lift = [0.012, 0.004, -0.004];
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        out[row * 5 + col] = sat[row * 3 + col] * (hi - lo) * warm[row];
      }
      out[row * 5 + 4] = (lo + lift[row]) * 255;
    }
    out[18] = 1;
    return out;
  }

  static final Paint _softLight = Paint()
    ..blendMode = BlendMode.softLight
    ..colorFilter = posterGrade
    ..color = const Color.fromRGBO(0, 0, 0, 0.42);

  /// Draws [image] cover-fitted into [dst] with alignment (-1..1). A
  /// [zoom] > 1 crops further around ([alignX], [alignY]).
  static void cover(Canvas canvas, ui.Image image, Rect dst,
      {double alignX = 0,
      double alignY = -0.55,
      double zoom = 1,
      bool grade = true,
      FilterQuality quality = FilterQuality.medium}) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final scale = math.max(dst.width / iw, dst.height / ih) * zoom;
    final sw = dst.width / scale, sh = dst.height / scale;
    final sx = (iw - sw) * (alignX + 1) / 2;
    final sy = (ih - sh) * (alignY + 1) / 2;
    final src = Rect.fromLTWH(sx, sy, sw, sh);
    final paint = Paint()..filterQuality = quality;
    if (grade) paint.colorFilter = posterGrade;
    canvas.drawImageRect(image, src, dst, paint);
    if (grade) {
      // Soft-light the image onto itself: a gentle S-curve.
      _softLight.filterQuality = quality;
      canvas.drawImageRect(image, src, dst, _softLight);
    }
  }

  /// Faint print vignette (multiplied).
  static void vignette(Canvas canvas, Rect rect, {double strength = 0.16}) {
    final r = math.max(rect.width, rect.height) * 0.75;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.multiply
        ..shader = ui.Gradient.radial(
          rect.center,
          r,
          [
            const Color(0xFFFFFFFF),
            const Color(0xFFFFFFFF),
            Color.fromRGBO(
                (255 * (1 - strength)).round(),
                (255 * (1 - strength * 0.95)).round(),
                (255 * (1 - strength * 0.85)).round(),
                1),
          ],
          const [0, 0.55, 1],
        ),
    );
  }

  /// The NextCue studio mark: a red disc with a play/cue notch, optional
  /// wordmark underneath. [d] = disc diameter. Returns the painted bounds.
  static Rect studioMark(
    Canvas canvas,
    Offset center,
    double d, {
    Color disc = LabelColors.brandRed,
    Color glyph = const Color(0xFFFFFFFF),
    Color? wordColor,
    double wordWidth = 0,
    TextRecorder? recorder,
  }) {
    final r = d / 2;
    canvas.drawCircle(center, r, Paint()..color = disc);
    // Inner ring.
    canvas.drawCircle(
        center,
        r * 0.78,
        Paint()
          ..color = glyph
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.09);
    // Play triangle, optically centred.
    final t = r * 0.42;
    final tri = Path()
      ..moveTo(center.dx - t * 0.62, center.dy - t)
      ..lineTo(center.dx + t * 1.0, center.dy)
      ..lineTo(center.dx - t * 0.62, center.dy + t)
      ..close();
    canvas.drawPath(tri, Paint()..color = glyph);
    var bounds = Rect.fromCircle(center: center, radius: r);
    if (wordColor != null && wordWidth > 0) {
      final f = FittedLabel.fit('NEXTCUE',
          family: LabelFonts.text,
          weight: FontWeight.w800,
          size: d * 0.36,
          maxWidth: wordWidth,
          trackingEm: 0.16,
          color: wordColor,
          ink: InkMetrics.figtree);
      final top = center.dy + r + d * 0.16;
      final box = Rect.fromLTWH(center.dx - wordWidth / 2, top, wordWidth, f.capHeight);
      bounds = bounds.expandToInclude(f.paintIn(canvas, box, recorder: recorder));
    }
    return bounds;
  }

  /// The "VHS" format logo: bold letters in a keyline box. [h] = height.
  static Rect vhsLogo(Canvas canvas, Rect box, Color color,
      {TextRecorder? recorder, bool filled = false, Color? knockout}) {
    final rr = RRect.fromRectAndRadius(box, Radius.circular(box.height * 0.12));
    if (filled) {
      canvas.drawRRect(rr, Paint()..color = color);
    } else {
      canvas.drawRRect(
          rr,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = box.height * 0.08);
    }
    final f = FittedLabel.fit('VHS',
        family: LabelFonts.text,
        weight: FontWeight.w800,
        size: box.height * 0.62,
        maxWidth: box.width * 0.78,
        maxHeight: box.height * 0.62,
        trackingEm: 0.04,
        color: filled ? (knockout ?? const Color(0xFFFFFFFF)) : color,
        ink: InkMetrics.figtree);
    f.paintIn(canvas, box, recorder: recorder);
    return box;
  }

  /// Small solid triangle (▶ / ◀) drawn as a path — the bundled fonts
  /// don't all carry the geometric shapes block.
  static Path triangle(Offset c, double h, {bool left = false}) {
    final w = h * 0.86;
    final dir = left ? -1.0 : 1.0;
    return Path()
      ..moveTo(c.dx - dir * w / 2, c.dy - h / 2)
      ..lineTo(c.dx + dir * w / 2, c.dy)
      ..lineTo(c.dx - dir * w / 2, c.dy + h / 2)
      ..close();
  }

  /// Diagonal stripes filling [rect] (clipped).
  static void diagonalStripes(Canvas canvas, Rect rect, List<Color> colors,
      double stripe, {double angle = -math.pi / 4}) {
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = colors.first);
    final p = Paint();
    final diag = rect.longestSide * 1.5 + rect.shortestSide;
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(angle);
    var i = 0;
    for (var x = -diag; x < diag; x += stripe) {
      p.color = colors[i % colors.length];
      if (i % colors.length != 0) {
        canvas.drawRect(Rect.fromLTWH(x, -diag, stripe, diag * 2), p);
      }
      i++;
    }
    canvas.restore();
  }
}
