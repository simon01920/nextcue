import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'label_palette.dart';
import 'label_print.dart';
import 'label_rng.dart';
import 'label_text.dart';
import 'tape_label_data.dart';

/// State stickers ("NEW" price-gun label, tape counter, BE KIND REWIND
/// roundel, NEW EP starburst) and rubber stamps. Stickers are the only
/// things allowed a (tiny) shadow; each gets its own paper grain. Sizes in
/// design units (0.1 mm).
class LabelStickers {
  LabelStickers._();

  static final Paint _shadow = Paint()
    ..color = const Color(0x33000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// Rough footprint of a state's sticker (before rotation).
  static Size sizeFor(TapeStateKind kind) => switch (kind) {
        TapeStateKind.notStarted => const Size(214, 112),
        TapeStateKind.watching => const Size(232, 124),
        TapeStateKind.completed => const Size(200, 200),
        TapeStateKind.newEpisode => const Size(222, 222),
      };

  /// Paints the sticker for [state] centred on [center], rotated [tilt].
  /// [maxWidth] bounds the footprint (the spine is 28 mm).
  static void paintForState(
    Canvas canvas,
    Offset center,
    TapeState state, {
    required bool isMovie,
    required double tilt,
    required ui.Image grain,
    required LabelRng rng,
    List<Color> grounds = const <Color>[],
    double scale = 1,
    TextRecorder? recorder,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);
    canvas.scale(scale);
    switch (state.kind) {
      case TapeStateKind.notStarted:
        _priceGun(canvas, grain, rng, grounds, recorder);
      case TapeStateKind.watching:
        _counter(canvas, state, isMovie, grain, recorder);
      case TapeStateKind.completed:
        _rewind(canvas, grain, rng, grounds, recorder);
      case TapeStateKind.newEpisode:
        _starburst(canvas, state, grain, grounds, recorder);
    }
    canvas.restore();
  }

  /// RGB distance 0..1.
  static double _dist(Color a, Color b) {
    final dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
    return math.sqrt(dr * dr + dg * dg + db * db) / math.sqrt(3);
  }

  /// Picks one of [options] that stands out from every colour in
  /// [grounds] (so a sticker never vanishes into the band under it).
  static T _distinct<T>(List<T> options, Color Function(T) colorOf,
      List<Color> grounds, LabelRng rng) {
    double score(T o) => grounds.isEmpty
        ? 1
        : grounds.map((g) => _dist(colorOf(o), g)).reduce(math.min);
    final ok = options.where((o) => score(o) > 0.27).toList();
    final pick = rng.nextDouble();
    if (ok.isNotEmpty) return ok[(pick * ok.length).floor().clamp(0, ok.length - 1)];
    return options.reduce((a, b) => score(a) >= score(b) ? a : b);
  }

  static void _shadowed(Canvas canvas, Path path, Color color, ui.Image grain,
      {double grainOpacity = 0.22}) {
    canvas.drawPath(path.shift(const Offset(0.6, 2.2)), _shadow);
    _fill.color = color;
    canvas.drawPath(path, _fill);
    canvas.save();
    canvas.clipPath(path);
    LabelPrint.grain(canvas, path.getBounds(), grain,
        opacity: grainOpacity, texel: 1.4);
    canvas.restore();
  }

  // ── NEW ───────────────────────────────────────────────────────────────
  static const List<Color> _fluoro = [
    Color(0xFFFF6A2B), // blaze orange
    Color(0xFFFFE347), // signal yellow
    Color(0xFFFF4F9A), // hot pink
    Color(0xFF8CF25E), // lime
  ];

  static void _priceGun(Canvas canvas, ui.Image grain, LabelRng rng,
      List<Color> grounds, TextRecorder? recorder) {
    final s = sizeFor(TapeStateKind.notStarted);
    final r = Rect.fromCenter(center: Offset.zero, width: s.width, height: s.height);
    final color = _distinct<Color>(_fluoro, (c) => c, grounds, rng);
    // Die-cut with shallow scalloped short ends, like a price-gun label.
    const bumps = 4;
    final bh = r.height / bumps;
    const sag = 5.0;
    final rad = Radius.circular(((bh / 2) * (bh / 2) + sag * sag) / (2 * sag));
    final path = Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.right, r.top);
    for (var i = 0; i < bumps; i++) {
      path.arcToPoint(Offset(r.right, r.top + bh * (i + 1)),
          radius: rad, clockwise: false);
    }
    path.lineTo(r.left, r.bottom);
    for (var i = bumps - 1; i >= 0; i--) {
      path.arcToPoint(Offset(r.left, r.top + bh * i),
          radius: rad, clockwise: false);
    }
    path.close();
    _shadowed(canvas, path, color, grain);
    final ink = color.computeLuminance() > 0.5
        ? const Color(0xFFC40A1A)
        : const Color(0xFF16110F);
    // Perforation ticks.
    _stroke
      ..color = ink.withValues(alpha: 0.5)
      ..strokeWidth = 2.2;
    for (final x in [r.left + 26.0, r.right - 26.0]) {
      for (var y = r.top + 12; y < r.bottom - 10; y += 14) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 7), _stroke);
      }
    }
    final title = FittedLabel.fit('NEW',
        family: LabelFonts.display,
        size: 64,
        maxWidth: r.width - 76,
        maxHeight: 60,
        trackingEm: 0.04,
        color: ink,
        ink: InkMetrics.anton);
    final sub = FittedLabel.fit('RELEASE',
        family: LabelFonts.text,
        weight: FontWeight.w800,
        size: 15,
        maxWidth: r.width - 80,
        maxHeight: 15,
        trackingEm: 0.22,
        color: ink,
        ink: InkMetrics.figtree);
    final total = title.capHeight + 9 + sub.capHeight;
    final top = -total / 2;
    title.paint(canvas, -title.width / 2, top + title.capHeight, recorder: recorder);
    sub.paint(canvas, -sub.width / 2, top + total, recorder: recorder);
  }

  // ── Tape counter ─────────────────────────────────────────────────────
  static void _counter(Canvas canvas, TapeState state, bool isMovie,
      ui.Image grain, TextRecorder? recorder) {
    final s = sizeFor(TapeStateKind.watching);
    final r = Rect.fromCenter(center: Offset.zero, width: s.width, height: s.height);
    final path = Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(9)));
    const silver = Color(0xFFD5D8D6);
    _shadowed(canvas, path, silver, grain, grainOpacity: 0.28);
    const ink = Color(0xFF1E2120);
    _stroke
      ..color = ink
      ..strokeWidth = 2.6;
    canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(7), const Radius.circular(5)), _stroke);
    // Caption.
    final cap = FittedLabel.fit('TAPE COUNTER',
        family: LabelFonts.text,
        weight: FontWeight.w800,
        size: 12.5,
        maxWidth: r.width - 40,
        maxHeight: 12.5,
        trackingEm: 0.2,
        color: ink,
        ink: InkMetrics.figtree);
    cap.paint(canvas, -cap.width / 2, r.top + 16 + cap.capHeight, recorder: recorder);
    // LCD window.
    final win = Rect.fromLTRB(r.left + 16, r.top + 38, r.right - 16, r.bottom - 15);
    _fill.color = const Color(0xFF151A12);
    canvas.drawRRect(RRect.fromRectAndRadius(win, const Radius.circular(4)), _fill);
    const lit = Color(0xFFB9F24C);
    final String digits;
    if (isMovie || state.total <= 0) {
      final pct = (state.progress.clamp(0.0, 1.0) * 100).round();
      digits = '${pct.toString().padLeft(2, '0')}%';
    } else {
      String two(int v) => v.toString().padLeft(2, '0');
      digits = '${two(state.watched)}/${two(state.total)}';
    }
    final inner = win.deflate(9);
    // ▶ then the digits.
    final triH = inner.height * 0.62;
    _fill.color = lit;
    canvas.drawPath(
        LabelPrint.triangle(Offset(inner.left + triH * 0.43, inner.center.dy), triH),
        _fill);
    final digitBox = Rect.fromLTRB(
        inner.left + triH * 0.86 + 10, inner.top, inner.right, inner.bottom);
    SevenSegment.paint(canvas, digits, digitBox, on: lit, ghost: lit.withValues(alpha: 0.08));
  }

  // ── BE KIND, REWIND ──────────────────────────────────────────────────
  static const List<(Color, Color, Color)> _roundels = [
    (Color(0xFFFFD23F), Color(0xFF1A1714), Color(0xFFD7141A)), // yellow
    (Color(0xFFF4F1E8), Color(0xFF1A1714), Color(0xFFD7141A)), // white
    (Color(0xFF39C6D9), Color(0xFF101820), Color(0xFFFFFFFF)), // cyan
  ];

  static void _rewind(Canvas canvas, ui.Image grain, LabelRng rng,
      List<Color> grounds, TextRecorder? recorder) {
    final d = sizeFor(TapeStateKind.completed).width;
    final rad = d / 2;
    final (bg, ink, hot) = _distinct(_roundels, (r) => r.$1, grounds, rng);
    final path = Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: rad));
    _shadowed(canvas, path, bg, grain);
    _stroke
      ..color = ink
      ..strokeWidth = 3;
    canvas.drawCircle(Offset.zero, rad - 8, _stroke);
    _stroke.strokeWidth = 1.6;
    canvas.drawCircle(Offset.zero, rad * 0.56, _stroke);
    const size = 20.0;
    final baseR = rad - 16 - size * InkMetrics.figtree.capTop;
    _arcText(canvas, 'BE KIND', baseR, size, ink, top: true, recorder: recorder);
    _arcText(canvas, 'REWIND', rad - 17, size, ink, top: false, recorder: recorder);
    // Dots between the words.
    _fill.color = hot;
    final dotR = rad - 16 - size * 0.36;
    canvas.drawCircle(Offset(-dotR, 0), 4, _fill);
    canvas.drawCircle(Offset(dotR, 0), 4, _fill);
    // ◀◀ in the middle.
    final h = rad * 0.5;
    canvas.drawPath(LabelPrint.triangle(Offset(-h * 0.36, 0), h, left: true), _fill);
    canvas.drawPath(LabelPrint.triangle(Offset(h * 0.36, 0), h, left: true), _fill);
  }

  /// Text on a circle. [top]: along the top arc reading clockwise with the
  /// baseline at [radius]; otherwise along the bottom arc, upright, with
  /// the baseline at [radius].
  static void _arcText(Canvas canvas, String text, double radius, double size,
      Color color,
      {required bool top, TextRecorder? recorder}) {
    final ls = size * 0.16;
    final chars = text.split('');
    final paras = <ui.Paragraph>[
      for (final c in chars)
        LabelText.paragraph(c,
            family: LabelFonts.text,
            size: size,
            weight: FontWeight.w800,
            color: color),
    ];
    final widths = [for (final p in paras) p.maxIntrinsicWidth];
    final total =
        widths.fold<double>(0, (a, b) => a + b) + ls * (chars.length - 1);
    final sweep = total / radius;
    var cum = 0.0;
    for (var i = 0; i < chars.length; i++) {
      final mid = (cum + widths[i] / 2) / radius;
      cum += widths[i] + ls;
      if (chars[i] == ' ') continue;
      final p = paras[i];
      canvas.save();
      if (top) {
        final theta = -math.pi / 2 - sweep / 2 + mid;
        canvas.rotate(theta + math.pi / 2);
        canvas.translate(0, -radius);
      } else {
        final theta = math.pi / 2 + sweep / 2 - mid;
        canvas.rotate(theta - math.pi / 2);
        canvas.translate(0, radius);
      }
      final pw = p.maxIntrinsicWidth;
      canvas.drawParagraph(p, Offset(-pw / 2, -p.alphabeticBaseline));
      recorder?.record(
          canvas,
          chars[i],
          Rect.fromLTRB(-pw / 2, -InkMetrics.figtree.capTop * size, pw / 2,
              InkMetrics.figtree.baseBottom * size));
      canvas.restore();
    }
  }

  // ── NEW EP ───────────────────────────────────────────────────────────
  static void _starburst(Canvas canvas, TapeState state, ui.Image grain,
      List<Color> grounds, TextRecorder? recorder) {
    final d = sizeFor(TapeStateKind.newEpisode).width;
    // Brand red, unless the spine is red right there: then signal yellow.
    final red = grounds.every((g) => _dist(g, LabelColors.brandRed) > 0.22);
    final burst = red ? LabelColors.brandRed : const Color(0xFFFFD200);
    final white = red ? const Color(0xFFFFF8EC) : const Color(0xFFC40A1A);
    final ro = d / 2, ri = ro * 0.8;
    const points = 18;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / points;
      final rr = i.isEven ? ro : ri;
      final p = Offset(math.cos(a) * rr, math.sin(a) * rr);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    _shadowed(canvas, path, burst, grain, grainOpacity: 0.18);
    _stroke
      ..color = white.withValues(alpha: 0.9)
      ..strokeWidth = 2;
    canvas.drawCircle(Offset.zero, ri * 0.86, _stroke);
    final code = state.nextCode;
    final title = FittedLabel.fit('NEW EP',
        family: LabelFonts.display,
        size: 50,
        maxWidth: ri * 1.42,
        maxHeight: 46,
        trackingEm: 0.03,
        color: white,
        ink: InkMetrics.anton);
    if (code == null || code.isEmpty) {
      title.paintIn(canvas, Rect.fromCenter(center: Offset.zero, width: ri * 1.42, height: title.capHeight),
          recorder: recorder);
      return;
    }
    final sub = FittedLabel.fit(code.toUpperCase(),
        family: LabelFonts.text,
        weight: FontWeight.w800,
        size: 17,
        maxWidth: ri * 1.2,
        maxHeight: 17,
        trackingEm: 0.08,
        color: white,
        ink: InkMetrics.figtree);
    final total = title.capHeight + 10 + sub.capHeight;
    final top = -total / 2;
    title.paint(canvas, -title.width / 2, top + title.capHeight, recorder: recorder);
    sub.paint(canvas, -sub.width / 2, top + total, recorder: recorder);
  }

  // ── Rubber stamp ─────────────────────────────────────────────────────
  /// An inked rubber stamp: double keyline box with [text], eroded by the
  /// grain so it reads as ink on paper, multiplied onto the label.
  static void stamp(
    Canvas canvas,
    Offset center,
    String text, {
    required Color color,
    required double tilt,
    required ui.Image speckle,
    double height = 64,
    double maxWidth = 260,
    TextRecorder? recorder,
  }) {
    final main = FittedLabel.fit(text.toUpperCase(),
        family: LabelFonts.display,
        size: height * 0.5,
        maxWidth: maxWidth - height * 0.5,
        maxHeight: height * 0.46,
        trackingEm: 0.08,
        color: color,
        ink: InkMetrics.anton);
    final w = math.min(maxWidth, main.width + height * 0.5);
    final box = Rect.fromCenter(center: Offset.zero, width: w, height: height);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);
    canvas.saveLayer(box.inflate(6), Paint()..blendMode = BlendMode.multiply);
    _stroke
      ..color = color
      ..strokeWidth = height * 0.055;
    canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(height * 0.14)), _stroke);
    _stroke.strokeWidth = height * 0.025;
    canvas.drawRRect(
        RRect.fromRectAndRadius(box.deflate(height * 0.1), Radius.circular(height * 0.08)),
        _stroke);
    main.paintIn(canvas, box.deflate(height * 0.18), recorder: recorder);
    // Ink that didn't take: speckled erosion.
    LabelPrint.grain(canvas, box.inflate(6), speckle,
        opacity: 0.85, texel: 1.6, mode: BlendMode.dstOut);
    canvas.restore();
    canvas.restore();
  }
}

/// Seven-segment "LCD" digits drawn as paths (crisp at any scale, and no
/// font needed). Supports 0-9, '/', ':', '%' and space.
class SevenSegment {
  SevenSegment._();

  // Segment bits: a b c d e f g.
  static const Map<String, int> _map = {
    '0': 0x3F, '1': 0x06, '2': 0x5B, '3': 0x4F, '4': 0x66,
    '5': 0x6D, '6': 0x7D, '7': 0x07, '8': 0x7F, '9': 0x6F, '-': 0x40,
  };

  static final Paint _p = Paint();

  /// Paints [text] fitted (left-aligned, vertically centred) into [box].
  static void paint(Canvas canvas, String text, Rect box,
      {required Color on, required Color ghost}) {
    // Width units: digit 1.0, '/' 0.55, ':' 0.35, '%' 0.9, gap 0.22.
    // '1' only lights the right-hand segments: give it a narrow cell so
    // "121" doesn't read as "12 1".
    double unitOf(String c) => switch (c) {
          '/' => 0.55,
          ':' => 0.35,
          '%' => 0.9,
          ' ' => 0.4,
          '1' => 0.48,
          _ => 1.0,
        };
    const gap = 0.24;
    final units = text.split('').fold<double>(0, (s, c) => s + unitOf(c) + gap) - gap;
    final dh0 = box.height;
    final dw0 = dh0 * 0.55;
    final dw = math.min(dw0, box.width / units);
    final dh = dw / 0.55;
    final top = box.center.dy - dh / 2;
    var x = box.left;
    for (final c in text.split('')) {
      final u = unitOf(c);
      final cell = Rect.fromLTWH(x, top, dw * u, dh);
      if (c == '1') {
        // A full-size digit cell whose right edge is this narrow cell's.
        final full = Rect.fromLTWH(cell.right - dw, top, dw, dh);
        _digit(canvas, full, 0x06, on);
      } else if (_map.containsKey(c)) {
        _digit(canvas, cell, 0x7F, ghost);
        _digit(canvas, cell, _map[c]!, on);
      } else if (c == '/') {
        _slash(canvas, cell, on);
      } else if (c == ':') {
        _p.color = on;
        final r = dw * 0.07;
        canvas.drawCircle(Offset(cell.center.dx, cell.top + dh * 0.32), r, _p);
        canvas.drawCircle(Offset(cell.center.dx, cell.top + dh * 0.68), r, _p);
      } else if (c == '%') {
        _percent(canvas, cell, on);
      }
      x += dw * (u + gap);
    }
  }

  static void _digit(Canvas canvas, Rect r, int bits, Color color) {
    _p.color = color;
    final h = r.height;
    final skew = h * 0.07; // italic lean
    final w = r.width - skew;
    final t = w * 0.2; // segment thickness
    final g = t * 0.22; // gap between segments
    Offset k(double x, double y) =>
        Offset(r.left + x + skew * (1 - y / h), r.top + y);
    final xl = t / 2, xr = w - t / 2;
    final yt = t / 2, ym = h / 2, yb = h - t / 2;
    Path hs(double y) => Path()
      ..addPolygon([
        k(xl + g, y),
        k(xl + g + t / 2, y - t / 2),
        k(xr - g - t / 2, y - t / 2),
        k(xr - g, y),
        k(xr - g - t / 2, y + t / 2),
        k(xl + g + t / 2, y + t / 2),
      ], true);
    Path vs(double x, double y0, double y1) => Path()
      ..addPolygon([
        k(x, y0 + g),
        k(x + t / 2, y0 + g + t / 2),
        k(x + t / 2, y1 - g - t / 2),
        k(x, y1 - g),
        k(x - t / 2, y1 - g - t / 2),
        k(x - t / 2, y0 + g + t / 2),
      ], true);
    final segs = <Path>[
      hs(yt), // a
      vs(xr, yt, ym), // b
      vs(xr, ym, yb), // c
      hs(yb), // d
      vs(xl, ym, yb), // e
      vs(xl, yt, ym), // f
      hs(ym), // g
    ];
    for (var i = 0; i < 7; i++) {
      if (bits & (1 << i) != 0) canvas.drawPath(segs[i], _p);
    }
  }

  static void _slash(Canvas canvas, Rect r, Color color) {
    _p.color = color;
    final t = r.height * 0.09;
    final path = Path()
      ..addPolygon([
        Offset(r.right - t * 0.2, r.top + t * 0.5),
        Offset(r.right - t * 0.2 - t, r.top + t * 0.5),
        Offset(r.left + t * 0.2, r.bottom - t * 0.5),
        Offset(r.left + t * 0.2 + t, r.bottom - t * 0.5),
      ], true);
    canvas.drawPath(path, _p);
  }

  static void _percent(Canvas canvas, Rect r, Color color) {
    _slash(canvas, r, color);
    _p.color = color;
    final d = r.width * 0.3;
    canvas.drawRect(Rect.fromLTWH(r.left, r.top + r.height * 0.08, d, d), _p);
    canvas.drawRect(
        Rect.fromLTWH(r.right - d, r.bottom - d - r.height * 0.08, d, d), _p);
  }
}
