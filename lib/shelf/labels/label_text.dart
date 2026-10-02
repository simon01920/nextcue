import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Bundled families (pubspec.yaml). Both cover every Slovak/Czech glyph;
/// the labels use nothing else.
class LabelFonts {
  LabelFonts._();
  static const String display = 'Anton';
  static const String text = 'Figtree';
}

/// Vertical ink extents of a font's *uppercase* repertoire, in em, measured
/// from the TTF outlines (fontTools, glyf yMax/yMin). Paragraph line boxes
/// are far taller than the caps, so fitting to them would waste a third of
/// a spine; fitting to these keeps type tight without ever clipping an
/// accent (Č, Ť, Ů) or a descender (Q, comma).
@immutable
class InkMetrics {
  const InkMetrics({
    required this.capTop,
    required this.accentTop,
    required this.ringTop,
    required this.bracketTop,
    required this.descender,
    required this.baseBottom,
  });

  /// Anton Regular (upm 2048): caps 0.859–0.870, Á/Č/Ť 1.101, Ů 1.229,
  /// ( ) 0.890, Q/comma/( −0.115.
  static const InkMetrics anton = InkMetrics(
    capTop: 0.872,
    accentTop: 1.104,
    ringTop: 1.232,
    bracketTop: 0.892,
    descender: 0.118,
    baseBottom: 0.012,
  );

  /// Figtree 300–800 (upm 1000), max over weights: caps 0.713–0.716,
  /// accents ≤ 0.932, Ů 0.964, ( ) 0.80, descenders −0.114.
  static const InkMetrics figtree = InkMetrics(
    capTop: 0.718,
    accentTop: 0.935,
    ringTop: 0.967,
    bracketTop: 0.802,
    descender: 0.116,
    baseBottom: 0.016,
  );

  final double capTop;
  final double accentTop;
  final double ringTop;
  final double bracketTop;
  final double descender;
  final double baseBottom;

  static const String _rings = 'ŮÅůå';
  static const String _brackets = '()[]{}|/\\';
  static const String _descending = 'QJ,;()[]{}ĄĘĮŲÇŞŢȘȚ|';

  /// Ink above the baseline (em) for [s].
  double topFor(String s) {
    var top = capTop;
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      if (_rings.contains(ch)) return ringTop;
      if (r > 0x7F && r != 0x2013 && r != 0x2014 && r != 0x2026 && r != 0xB7) {
        if (accentTop > top) top = accentTop;
      } else if (_brackets.contains(ch)) {
        if (bracketTop > top) top = bracketTop;
      }
    }
    return top;
  }

  /// Ink below the baseline (em) for [s].
  double bottomFor(String s) {
    for (final r in s.runes) {
      if (_descending.contains(String.fromCharCode(r))) return descender;
    }
    return baseBottom;
  }
}

/// A text box that was painted, in atlas pixels. Collected only when a
/// recorder is installed (tests), to assert nothing overflows its region.
@immutable
class TextPlacement {
  const TextPlacement(this.region, this.text, this.rect);
  final String region;
  final String text;
  final Rect rect;

  @override
  String toString() => 'TextPlacement($region, "$text", $rect)';
}

/// Records painted text boxes in device (atlas pixel) space.
class TextRecorder {
  final List<TextPlacement> placements = <TextPlacement>[];
  String region = '';

  void record(Canvas canvas, String text, Rect local) {
    placements.add(TextPlacement(region, text, transformRect(canvas.getTransform(), local)));
  }

  static Rect transformRect(Float64List m, Rect r) {
    Offset t(double x, double y) {
      // Column-major 4×4.
      final w = m[3] * x + m[7] * y + m[15];
      return Offset(
        (m[0] * x + m[4] * y + m[12]) / w,
        (m[1] * x + m[5] * y + m[13]) / w,
      );
    }

    final a = t(r.left, r.top),
        b = t(r.right, r.top),
        c = t(r.left, r.bottom),
        d = t(r.right, r.bottom);
    double mn(double p, double q, double s, double u) =>
        [p, q, s, u].reduce((x, y) => x < y ? x : y);
    double mx(double p, double q, double s, double u) =>
        [p, q, s, u].reduce((x, y) => x > y ? x : y);
    return Rect.fromLTRB(mn(a.dx, b.dx, c.dx, d.dx), mn(a.dy, b.dy, c.dy, d.dy),
        mx(a.dx, b.dx, c.dx, d.dx), mx(a.dy, b.dy, c.dy, d.dy));
  }
}

/// Paragraph factory with a small LRU of laid-out paragraphs, so measuring
/// and painting the same run (and recomposing the same title for the hero
/// after the shelf) never builds a paragraph twice.
class LabelText {
  LabelText._();

  static const double _wide = 100000;
  static final LinkedHashMap<String, ui.Paragraph> _lru =
      LinkedHashMap<String, ui.Paragraph>();
  static const int _lruMax = 600;
  static final Map<String, ui.ParagraphStyle> _paragraphStyles = {};

  /// Paragraphs built so far (diagnostics).
  static int builds = 0;

  /// Drops cached paragraphs (tests measuring cold compose time).
  @visibleForTesting
  static void clearCache() => _lru.clear();

  static ui.ParagraphStyle _pStyle(TextAlign align, int? maxLines, bool ellipsis,
      double? height) {
    final key = '${align.index}|$maxLines|$ellipsis|$height';
    return _paragraphStyles[key] ??= ui.ParagraphStyle(
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: ellipsis ? '…' : null,
      height: height,
      textHeightBehavior: const ui.TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );
  }

  /// A single-style paragraph laid out at [width] (default: unbounded,
  /// single line, left-aligned).
  static ui.Paragraph paragraph(
    String text, {
    required String family,
    required double size,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
    Color color = const Color(0xFF000000),
    double width = _wide,
    TextAlign align = TextAlign.left,
    int? maxLines,
    bool ellipsis = false,
    double? height,
    double strokeWidth = 0,
    bool cache = true,
  }) {
    final key = cache
        ? '$family|${size.toStringAsFixed(3)}|${weight.value}|'
            '${letterSpacing.toStringAsFixed(3)}|${color.toARGB32()}|$strokeWidth|'
            '${width.toStringAsFixed(2)}|${align.index}|$maxLines|$ellipsis|$height|$text'
        : '';
    if (cache) {
      final hit = _lru.remove(key);
      if (hit != null) {
        _lru[key] = hit;
        return hit;
      }
    }
    final b = ui.ParagraphBuilder(_pStyle(align, maxLines, ellipsis, height))
      ..pushStyle(ui.TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: strokeWidth > 0 ? null : color,
        foreground: strokeWidth > 0
            ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = color)
            : null,
        height: height,
      ))
      ..addText(text);
    final p = b.build()..layout(ui.ParagraphConstraints(width: width));
    builds++;
    if (cache) {
      _lru[key] = p;
      if (_lru.length > _lruMax) _lru.remove(_lru.keys.first);
    }
    return p;
  }

  /// Ink width (advance minus the trailing half-spacing on both ends) of a
  /// single line, and where the ink starts relative to the paragraph
  /// origin. SkParagraph puts letterSpacing/2 before every glyph.
  static double inkWidth(ui.Paragraph p, double letterSpacing) =>
      p.maxIntrinsicWidth - letterSpacing;

  /// Draws a single line so its ink box starts at [inkLeft] and its
  /// baseline sits on [baseline]. Returns the ink rect (cap/accent aware
  /// when [ink] is given).
  static Rect drawLine(
    Canvas canvas,
    ui.Paragraph p, {
    required double inkLeft,
    required double baseline,
    required double letterSpacing,
    required double size,
    InkMetrics? ink,
    String? text,
    TextRecorder? recorder,
  }) {
    canvas.drawParagraph(
        p, Offset(inkLeft - letterSpacing / 2, baseline - p.alphabeticBaseline));
    final w = inkWidth(p, letterSpacing);
    final Rect r;
    if (ink != null && text != null) {
      r = Rect.fromLTRB(inkLeft, baseline - ink.topFor(text) * size, inkLeft + w,
          baseline + ink.bottomFor(text) * size);
    } else {
      // Mixed case: use the font's line box.
      r = Rect.fromLTRB(inkLeft, baseline - p.alphabeticBaseline, inkLeft + w,
          baseline - p.alphabeticBaseline + p.height);
    }
    if (recorder != null) recorder.record(canvas, text ?? '', r);
    return r;
  }
}

/// A single line of small text (captions, catalogue numbers, meta lines)
/// shrunk to fit a box: never overflows, never wraps.
class FittedLabel {
  FittedLabel._(this.text, this.paragraph, this.size, this.letterSpacing,
      this.ink, this.width);

  /// Fits [text] into [maxWidth] × [maxHeight] (ink box for uppercase
  /// [ink] metrics; line box otherwise), starting at [size] and shrinking.
  factory FittedLabel.fit(
    String text, {
    required String family,
    required double size,
    required double maxWidth,
    double? maxHeight,
    FontWeight weight = FontWeight.w600,
    double trackingEm = 0,
    Color color = const Color(0xFF000000),
    InkMetrics? ink,
  }) {
    var s = size;
    if (maxHeight != null) {
      final em = ink == null
          ? (family == LabelFonts.display ? 1.505 : 1.2)
          : ink.topFor(text) + ink.bottomFor(text);
      if (s * em > maxHeight) s = maxHeight / em;
    }
    // Measure at s, then scale linearly (advances are linear in size).
    var ls = trackingEm * s;
    var p = LabelText.paragraph(text,
        family: family, size: s, weight: weight, letterSpacing: ls, color: color);
    var w = LabelText.inkWidth(p, ls);
    if (w > maxWidth && w > 0) {
      s = s * maxWidth / w * 0.995;
      ls = trackingEm * s;
      p = LabelText.paragraph(text,
          family: family, size: s, weight: weight, letterSpacing: ls, color: color);
      w = LabelText.inkWidth(p, ls);
      var guard = 0;
      while (w > maxWidth && guard++ < 6) {
        s *= 0.97;
        ls = trackingEm * s;
        p = LabelText.paragraph(text,
            family: family, size: s, weight: weight, letterSpacing: ls, color: color);
        w = LabelText.inkWidth(p, ls);
      }
    }
    return FittedLabel._(text, p, s, ls, ink, w);
  }

  final String text;
  final ui.Paragraph paragraph;
  final double size;
  final double letterSpacing;
  final InkMetrics? ink;
  final double width;

  double get capHeight => (ink?.capTop ?? 0.72) * size;

  /// Paint with ink starting at [inkLeft] and the baseline at [baseline].
  Rect paint(Canvas canvas, double inkLeft, double baseline,
          {TextRecorder? recorder}) =>
      LabelText.drawLine(canvas, paragraph,
          inkLeft: inkLeft,
          baseline: baseline,
          letterSpacing: letterSpacing,
          size: size,
          ink: ink,
          text: text,
          recorder: recorder);

  /// Paint horizontally aligned inside [box] ([align] -1 left, 0 centre,
  /// 1 right) with the caps optically centred vertically.
  Rect paintIn(Canvas canvas, Rect box,
      {double align = 0, TextRecorder? recorder}) {
    final x = box.left + (box.width - width) * (align + 1) / 2;
    final double baseline;
    if (ink != null) {
      final top = ink!.topFor(text) * size, bottom = ink!.bottomFor(text) * size;
      var b = box.center.dy + capHeight / 2;
      if (b - top < box.top) b = box.top + top;
      if (b + bottom > box.bottom) b = box.bottom - bottom;
      baseline = b;
    } else {
      baseline = box.center.dy - paragraph.height / 2 + paragraph.alphabeticBaseline;
    }
    return paint(canvas, x, baseline, recorder: recorder);
  }
}
