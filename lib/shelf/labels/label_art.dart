import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'label_palette.dart';
import 'label_print.dart';
import 'label_text.dart';

/// What a clear logo looks like, sampled once per image: its average ink
/// colour (alpha-weighted), how much of its box it covers, and the tight
/// bounds of its ink (TVDB clear logos often carry transparent margins).
/// Drives trimming and the contrast treatment on coloured grounds.
@immutable
class LogoInfo {
  const LogoInfo({
    required this.meanColor,
    required this.coverage,
    this.bounds = const Rect.fromLTWH(0, 0, 1, 1),
  });

  /// Alpha-weighted average colour of the logo's opaque pixels.
  final Color meanColor;

  /// 0..1 share of its trimmed box the logo actually inks.
  final double coverage;

  /// Inked area as a fraction of the image (0..1 on both axes).
  final Rect bounds;

  static final Expando<Future<LogoInfo>> _cache = Expando<Future<LogoInfo>>('LogoInfo');

  static const int sampleW = 96, sampleH = 48;

  /// Samples [logo] (cached per image instance).
  static Future<LogoInfo> of(ui.Image logo) => _cache[logo] ??= _sample(logo);

  static Future<LogoInfo> _sample(ui.Image logo) async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      const Rect.fromLTWH(0, 0, sampleW * 1.0, sampleH * 1.0),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final pic = rec.endRecording();
    final img = await pic.toImage(sampleW, sampleH);
    pic.dispose();
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (data == null) {
      return const LogoInfo(meanColor: Color(0xFFFFFFFF), coverage: 0.5);
    }
    return fromRgba(data.buffer.asUint8List());
  }

  /// Pure analysis of a [width]-wide thumbnail in *premultiplied* RGBA
  /// (what `rawRgba` returns; summing premultiplied channels and dividing
  /// by summed alpha is exactly the alpha-weighted mean colour). Exposed
  /// for tests.
  static LogoInfo fromRgba(Uint8List px, {int width = sampleW}) {
    double r = 0, g = 0, b = 0, a = 0;
    final n = px.length ~/ 4;
    final height = n ~/ width;
    var x0 = width, y0 = height, x1 = -1, y1 = -1;
    for (var i = 0; i < n; i++) {
      final o = i * 4;
      final al = px[o + 3];
      r += px[o];
      g += px[o + 1];
      b += px[o + 2];
      a += al / 255.0;
      if (al > 10) {
        final x = i % width, y = i ~/ width;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
    if (a <= 0 || x1 < 0) {
      return const LogoInfo(meanColor: Color(0xFFFFFFFF), coverage: 0);
    }
    // One sample of slack each side: the thumbnail is a filtered average.
    final bounds = Rect.fromLTRB(
      math.max(0, x0 - 1) / width,
      math.max(0, y0 - 1) / height,
      math.min(width, x1 + 2) / width,
      math.min(height, y1 + 2) / height,
    );
    return LogoInfo(
      meanColor: Color.fromARGB(255, (r / a).round().clamp(0, 255),
          (g / a).round().clamp(0, 255), (b / a).round().clamp(0, 255)),
      coverage: a / math.max(1, bounds.width * bounds.height * n),
      bounds: bounds,
    );
  }
}

/// How a logo gets printed on a given ground.
enum LogoTreatment {
  /// Its own colours: it reads fine on this ground.
  asIs,

  /// Its own colours plus a keyline in paper or ink (whichever reads on
  /// the ground) — how a printer saves a logo that would otherwise vanish
  /// into the ground colour, without flattening its design.
  keyline,
}

/// Printing artwork (logos, photos) into label regions.
class LabelArt {
  LabelArt._();

  /// Contrast below which a logo is reprinted in one colour.
  static const double minLogoContrast = 2.1;

  static LogoTreatment treatmentFor(LogoInfo info, Color ground) =>
      LabelColors.contrast(info.meanColor, ground) >= minLogoContrast
          ? LogoTreatment.asIs
          : LogoTreatment.keyline;

  /// Size of the logo's inked area in image pixels (margins trimmed).
  static Size logoSize(ui.Image logo, LogoInfo? info) {
    final b = info?.bounds ?? const Rect.fromLTWH(0, 0, 1, 1);
    return Size(b.width * logo.width, b.height * logo.height);
  }

  /// Contains [logo] (aspect preserved) inside [box]. With [rotate] the
  /// logo is turned +90° so it reads top-to-bottom like spine type; [box]
  /// is then the spine slot (tall) and the logo's width runs along its
  /// height. [align] places it along the long axis (-1 start, 0 centre,
  /// 1 end). Returns the painted rect (canvas-local, unrotated box space).
  static Rect logo(
    Canvas canvas,
    ui.Image logo,
    LogoInfo? info,
    Rect box, {
    required Color ground,
    bool rotate = false,
    double align = 0,
    double maxScale = double.infinity,
    TextRecorder? recorder,
  }) {
    // Trim transparent margins (ink bounds from the sampled thumbnail).
    final b = info?.bounds ?? const Rect.fromLTWH(0, 0, 1, 1);
    final src = Rect.fromLTRB(b.left * logo.width, b.top * logo.height,
        b.right * logo.width, b.bottom * logo.height);
    final iw = src.width, ih = src.height;
    // Footprint of the logo in the box's orientation.
    final fw = rotate ? ih : iw, fh = rotate ? iw : ih;
    final sc = math.min(math.min(box.width / fw, box.height / fh), maxScale);
    final w = fw * sc, h = fh * sc;
    final double x, y;
    if (rotate) {
      x = box.left + (box.width - w) / 2;
      y = box.top + (box.height - h) * (align + 1) / 2;
    } else {
      x = box.left + (box.width - w) * (align + 1) / 2;
      y = box.top + (box.height - h) / 2;
    }
    final treat = info == null ? LogoTreatment.asIs : treatmentFor(info, ground);
    // Keyline width; the logo shrinks by it so the outline stays in [box].
    final k = treat == LogoTreatment.keyline
        ? (math.min(w, h) * 0.035).clamp(3.0, 12.0)
        : 0.0;
    final s2 = k == 0 ? sc : sc * math.max(0.1, 1 - 2 * k / math.min(w, h));
    final w2 = fw * s2, h2 = fh * s2;
    final placed = Rect.fromLTWH(x + (w - w2) / 2, y + (h - h2) / 2, w2, h2);
    canvas.save();
    // Local frame: the logo's own (unrotated) rect at the origin.
    if (rotate) {
      // Logo top faces the box's right side (reads top-to-bottom).
      canvas.translate(placed.right, placed.top);
      canvas.rotate(math.pi / 2);
    } else {
      canvas.translate(placed.left, placed.top);
    }
    final dst = Rect.fromLTWH(0, 0, iw * s2, ih * s2);
    if (k > 0) {
      // Dilate the logo's silhouette by drawing it round a ring of offsets
      // in the keyline colour (works the same on every backend).
      final ring = Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.mode(LabelColors.on(ground), BlendMode.srcIn);
      const steps = 16;
      for (var i = 0; i < steps; i++) {
        final a = i * 2 * math.pi / steps;
        canvas.drawImageRect(
            logo, src, dst.shift(Offset(math.cos(a) * k, math.sin(a) * k)), ring);
      }
    }
    canvas.drawImageRect(logo, src, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
    final footprint = placed.inflate(k);
    recorder?.record(canvas, '[logo]', footprint);
    return footprint;
  }

  /// A photograph printed into [dst]: cover-fitted, graded, faint
  /// vignette. [alignX]/[alignY] -1..1, [zoom] ≥ 1 crops tighter.
  static void photo(Canvas canvas, ui.Image image, Rect dst,
      {double alignX = 0,
      double alignY = 0,
      double zoom = 1,
      double vignette = 0.18}) {
    LabelPrint.cover(canvas, image, dst, alignX: alignX, alignY: alignY, zoom: zoom);
    if (vignette > 0) LabelPrint.vignette(canvas, dst, strength: vignette);
  }

  /// A soft ink scrim rising from the bottom of [r] (for type or a logo
  /// printed over a photo). Flat print, not a lighting effect.
  static void scrim(Canvas canvas, Rect r, Color ink,
      {double from = 0.45, double strength = 0.82}) {
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topCenter,
          r.bottomCenter,
          [ink.withValues(alpha: 0), ink.withValues(alpha: 0), ink.withValues(alpha: strength)],
          [0, from, 1],
        ),
    );
  }
}
