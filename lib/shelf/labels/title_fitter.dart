import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'label_text.dart';

/// Where lines sit along an axis of the fit box.
enum TitleAlign { start, center, end }

/// How far down the fitting ladder a title had to go.
enum TitleFitStage {
  /// One line at the largest size the box allows.
  fitted,

  /// One line, shrunk (still ≥ the minimum size).
  shrunk,

  /// One line at the minimum size with tightened tracking.
  tightened,

  /// Broken into several parallel lines.
  wrapped,

  /// Truncated with an ellipsis (last resort).
  ellipsized,
}

/// Typographic rules for one title slot.
@immutable
class TitleFitSpec {
  const TitleFitSpec({
    this.fontFamily = LabelFonts.display,
    this.fontWeight = FontWeight.w400,
    this.ink = InkMetrics.anton,
    required this.maxFontSize,
    required this.minFontSize,
    double? minFontSizeMultiLine,
    this.trackingEm = 0.01,
    this.minTrackingEm = -0.02,
    this.maxLines = 2,
    this.lineGapEm = 0.14,
    this.mainAlign = TitleAlign.center,
    this.crossAlign = TitleAlign.center,
    this.uppercase = true,
  }) : minFontSizeMultiLine = minFontSizeMultiLine ?? minFontSize * 0.8;

  final String fontFamily;
  final FontWeight fontWeight;
  final InkMetrics ink;

  /// Size cap (layout units); the box height usually limits first.
  final double maxFontSize;

  /// Smallest size for a single line before tracking is tightened.
  final double minFontSize;

  /// Smallest size once the title is broken into lines.
  final double minFontSizeMultiLine;

  /// Preferred letter spacing, em.
  final double trackingEm;

  /// Tightest letter spacing, em.
  final double minTrackingEm;
  final int maxLines;

  /// Gap between one line's ink and the next one's, em.
  final double lineGapEm;

  /// Alignment along the line (the spine's length).
  final TitleAlign mainAlign;

  /// Alignment of the line block across lines (the spine's width).
  final TitleAlign crossAlign;
  final bool uppercase;

  String get cacheKey => '$fontFamily|${fontWeight.value}|$maxFontSize|$minFontSize|'
      '$minFontSizeMultiLine|$trackingEm|$minTrackingEm|$maxLines|$lineGapEm|'
      '${mainAlign.index}|${crossAlign.index}|$uppercase';
}

/// One laid-out line. Coordinates are in the fit box frame: x along the
/// line, y across lines, origin top-left of the available box.
@immutable
class FittedLine {
  const FittedLine({
    required this.text,
    required this.inkBox,
    required this.baseline,
  });

  final String text;

  /// Ink box (advance width × cap/accent/descender extent).
  final Rect inkBox;
  final double baseline;
}

/// Result of [TitleFitter.fit]: pure layout metrics plus a painter.
class TitleFit {
  TitleFit._({
    required this.source,
    required this.text,
    required this.spec,
    required this.available,
    required this.fontSize,
    required this.letterSpacing,
    required this.lines,
    required this.stage,
  });

  final String source;

  /// Case-mapped text that was fitted (before line breaking).
  final String text;
  final TitleFitSpec spec;
  final Size available;
  final double fontSize;

  /// Absolute letter spacing (layout units).
  final double letterSpacing;
  final List<FittedLine> lines;
  final TitleFitStage stage;

  double get trackingEm => fontSize == 0 ? 0 : letterSpacing / fontSize;
  bool get wrapped => lines.length > 1;
  bool get ellipsized => stage == TitleFitStage.ellipsized;

  /// Union of all line ink boxes.
  Rect get inkBounds => lines
      .map((l) => l.inkBox)
      .reduce((a, b) => a.expandToInclude(b));

  /// True if any ink leaves the available box (never, by construction —
  /// tests assert it).
  bool get overflows {
    const eps = 0.01;
    final b = inkBounds;
    return b.left < -eps ||
        b.top < -eps ||
        b.right > available.width + eps ||
        b.bottom > available.height + eps;
  }

  /// Paints the title with the box's top-left at [origin] in [color].
  /// Returns the painted ink bounds in the canvas' local space.
  Rect paint(Canvas canvas, Offset origin,
      {Color color = const Color(0xFF000000),
      double strokeWidth = 0,
      TextRecorder? recorder}) {
    for (final line in lines) {
      final p = LabelText.paragraph(
        line.text,
        family: spec.fontFamily,
        size: fontSize,
        weight: spec.fontWeight,
        letterSpacing: letterSpacing,
        color: color,
        strokeWidth: strokeWidth,
      );
      LabelText.drawLine(
        canvas,
        p,
        inkLeft: origin.dx + line.inkBox.left,
        baseline: origin.dy + line.baseline,
        letterSpacing: letterSpacing,
        size: fontSize,
        ink: spec.ink,
        text: line.text,
        recorder: recorder,
      );
    }
    return inkBounds.shift(origin);
  }

  @override
  String toString() =>
      'TitleFit(${stage.name}, size ${fontSize.toStringAsFixed(2)}, '
      'track ${trackingEm.toStringAsFixed(3)}em, lines ${lines.map((l) => l.text).toList()})';
}

class _Run {
  const _Run(this.advancePerEm, this.spacingUnits);

  /// Advance width at size 1 with no letter spacing.
  final double advancePerEm;

  /// How many letter-spacing increments the run's advance contains
  /// (one per grapheme cluster).
  final double spacingUnits;

  /// Ink width at [size] with [trackingEm].
  double inkWidth(double size, double trackingEm) =>
      size * (advancePerEm + (spacingUnits - 1) * trackingEm);
}

/// Fits a title into a box following docs/LABELS.md:
/// largest size that fits → shrink to a minimum → tighten tracking →
/// break into parallel lines at the word boundary nearest the middle →
/// ellipsis as the last resort. Pure: the result depends only on the
/// inputs and the loaded fonts.
class TitleFitter {
  TitleFitter._();

  static const double _ref = 100;
  static final LinkedHashMap<String, _Run> _runs = LinkedHashMap();
  static final LinkedHashMap<String, TitleFit> _fits = LinkedHashMap();

  /// Measures a run (cached). Exposed for tests.
  static double inkWidthOf(String text, TitleFitSpec spec, double size,
          double trackingEm) =>
      _measure(text, spec).inkWidth(size, trackingEm);

  static _Run _measure(String text, TitleFitSpec spec) {
    final key = '${spec.fontFamily}|${spec.fontWeight.value}|$text';
    final hit = _runs.remove(key);
    if (hit != null) return _runs[key] = hit;
    final p0 = LabelText.paragraph(text,
        family: spec.fontFamily, size: _ref, weight: spec.fontWeight, cache: false);
    final p1 = LabelText.paragraph(text,
        family: spec.fontFamily,
        size: _ref,
        weight: spec.fontWeight,
        letterSpacing: _ref * 0.1,
        cache: false);
    final w0 = p0.maxIntrinsicWidth;
    final units = (p1.maxIntrinsicWidth - w0) / (_ref * 0.1);
    final run = _Run(w0 / _ref, units.roundToDouble());
    _runs[key] = run;
    if (_runs.length > 2000) _runs.remove(_runs.keys.first);
    return run;
  }

  /// Locale-correct uppercase for Slovak/Czech (Unicode default mapping:
  /// ľ→Ľ, ť→Ť, ď→Ď, ň→Ň, ô→Ô, ů→Ů, ř→Ř; ß→SS), whitespace collapsed.
  static String caseMap(String s, {bool uppercase = true}) {
    final t = s.replaceAll(RegExp(r'[\s ]+'), ' ').trim();
    return uppercase ? t.toUpperCase() : t;
  }

  static final RegExp _punctOnly = RegExp(r'^[\p{P}\p{S}]+$', unicode: true);
  static final RegExp _lowerSingle = RegExp(r'^\p{Ll}$', unicode: true);
  static final RegExp _numeral = RegExp(r'^(?:[IVX]{1,4}|\d{1,3})[.,:;!?]?$');

  /// Splits a title (in its *original* case) into unbreakable tokens:
  /// * punctuation-only words (– — - : & /) stay with the previous word,
  ///   so a line never starts with a dash;
  /// * numerals ("Epizóda V", "Rocky II", "Part 2") stay with the
  ///   previous word;
  /// * one-letter lowercase words — the Slovak/Czech prepositions and
  ///   conjunctions "v z k s a i o u" — stay with the next word, as
  ///   Czech/Slovak typesetting requires.
  static List<String> tokens(String text) {
    final raw = text
        .replaceAll(RegExp(r'[\s ]+'), ' ')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final out = <String>[];
    for (final w in raw) {
      if (out.isNotEmpty && (_punctOnly.hasMatch(w) || _numeral.hasMatch(w))) {
        out[out.length - 1] = '${out.last} $w';
      } else {
        out.add(w);
      }
    }
    final merged = <String>[];
    var carry = '';
    for (var i = 0; i < out.length; i++) {
      final w = carry.isEmpty ? out[i] : '$carry ${out[i]}';
      if (_lowerSingle.hasMatch(out[i]) && i < out.length - 1) {
        carry = w;
      } else {
        merged.add(w);
        carry = '';
      }
    }
    if (carry.isNotEmpty) merged.add(carry);
    return merged;
  }

  /// Fits [title] into [available] (width = along the line, height =
  /// across lines). Results are cached.
  static TitleFit fit(String title, Size available, TitleFitSpec spec) {
    final key = '${spec.cacheKey}|${available.width.toStringAsFixed(2)}x'
        '${available.height.toStringAsFixed(2)}|$title';
    final hit = _fits.remove(key);
    if (hit != null) return _fits[key] = hit;
    final f = _fit(title, available, spec);
    _fits[key] = f;
    if (_fits.length > 400) _fits.remove(_fits.keys.first);
    return f;
  }

  static TitleFit _fit(String title, Size available, TitleFitSpec spec) {
    final text = caseMap(title, uppercase: spec.uppercase);
    final w = available.width, h = available.height;
    final ink = spec.ink;
    // Break rules need the original case (preposition "v" vs numeral "V").
    final srcToks = tokens(title);
    final toks = srcToks.isEmpty
        ? <String>[' ']
        : [for (final t in srcToks) caseMap(t, uppercase: spec.uppercase)];
    final maxLines = math.max(1, math.min(spec.maxLines, toks.length));

    for (var k = 1; k <= maxLines; k++) {
      final lines = k == 1 ? [toks.join(' ')] : _breakInto(toks, k, spec);
      final inkEm = _stackEm(lines, spec);
      final sizeCross = h / inkEm;
      final runs = lines.map((l) => _measure(l, spec)).toList();
      double widestPerEm(double t) =>
          runs.map((r) => r.inkWidth(1, t)).reduce(math.max);
      final sizeMain = w / widestPerEm(spec.trackingEm);
      var size = math.min(spec.maxFontSize, math.min(sizeCross, sizeMain));
      final minSize = k == 1 ? spec.minFontSize : spec.minFontSizeMultiLine;
      final floor = math.min(minSize, math.min(sizeCross, spec.maxFontSize));
      if (size >= floor - 1e-6) {
        final stage = k > 1
            ? TitleFitStage.wrapped
            : (size >= math.min(spec.maxFontSize, sizeCross) - 1e-6
                ? TitleFitStage.fitted
                : TitleFitStage.shrunk);
        return _layout(title, text, lines, available, spec, size * 0.999,
            spec.trackingEm, stage);
      }
      // Tighten tracking at the floor size.
      size = floor;
      var t = spec.trackingEm;
      for (final r in runs) {
        if (r.spacingUnits > 1) {
          final need = (w / size - r.advancePerEm) / (r.spacingUnits - 1);
          t = math.min(t, need);
        } else if (r.inkWidth(size, 0) > w) {
          t = double.negativeInfinity;
        }
      }
      if (t >= spec.minTrackingEm - 1e-9) {
        return _layout(
            title,
            text,
            lines,
            available,
            spec,
            size * 0.999,
            t,
            k == 1 ? TitleFitStage.tightened : TitleFitStage.wrapped);
      }
    }

    // Ellipsis: fill lines greedily at the floor size and tightest
    // tracking; the last line takes the rest, truncated with "…".
    final k = maxLines;
    final t = spec.minTrackingEm;
    final minSize = k == 1 ? spec.minFontSize : spec.minFontSizeMultiLine;
    // Size from the cross axis with worst-case ink (accents + descender).
    final worstEm = k * (ink.accentTop + ink.descender) + (k - 1) * spec.lineGapEm;
    final size =
        math.min(minSize, math.min(spec.maxFontSize, h / worstEm)) * 0.999;
    final lines = <String>[];
    var i = 0;
    for (var line = 0; line < k && i < toks.length; line++) {
      if (line == k - 1) {
        lines.add(_truncate(toks.sublist(i).join(' '), w, size, t, spec));
        i = toks.length;
        break;
      }
      var cur = toks[i];
      if (_measure(cur, spec).inkWidth(size, t) > w) {
        // A single word wider than the line: it goes last, truncated.
        lines.add(_truncate(toks.sublist(i).join(' '), w, size, t, spec));
        i = toks.length;
        break;
      }
      i++;
      while (i < toks.length) {
        final next = '$cur ${toks[i]}';
        if (_measure(next, spec).inkWidth(size, t) > w) break;
        cur = next;
        i++;
      }
      lines.add(cur);
    }
    if (i < toks.length) {
      lines[lines.length - 1] = _truncate(
          '${lines.last} ${toks.sublist(i).join(' ')}', w, size, t, spec);
    }
    return _layout(title, text, lines, available, spec, size, t,
        TitleFitStage.ellipsized);
  }

  /// Total ink height in em of [lines] stacked with the spec's gap.
  static double _stackEm(List<String> lines, TitleFitSpec spec) {
    var em = 0.0;
    for (final l in lines) {
      em += spec.ink.topFor(l) + spec.ink.bottomFor(l);
    }
    return em + (lines.length - 1) * spec.lineGapEm;
  }

  /// k = 2: the word boundary nearest the middle (by measured width).
  /// k > 2: the split minimising the widest line.
  static List<String> _breakInto(List<String> toks, int k, TitleFitSpec spec) {
    final widths = toks.map((t) => _measure(t, spec).advancePerEm).toList();
    final space = _measure('A A', spec).advancePerEm -
        2 * _measure('A', spec).advancePerEm;
    double span(int a, int b) {
      var s = 0.0;
      for (var i = a; i < b; i++) {
        s += widths[i];
      }
      return s + (b - a - 1) * space;
    }

    if (k == 2) {
      final total = span(0, toks.length);
      var best = 1;
      var bestD = double.infinity;
      for (var i = 1; i < toks.length; i++) {
        final d = (span(0, i) + space / 2 - total / 2).abs();
        if (d < bestD - 1e-9) {
          bestD = d;
          best = i;
        }
      }
      return [toks.sublist(0, best).join(' '), toks.sublist(best).join(' ')];
    }
    // Exhaustive search over break positions (titles have few words).
    List<int>? bestCuts;
    var bestScore = double.infinity;
    void search(List<int> cuts, int from) {
      if (cuts.length == k - 1) {
        final bounds = [0, ...cuts, toks.length];
        var mx = 0.0, sq = 0.0;
        for (var i = 0; i < k; i++) {
          final s = span(bounds[i], bounds[i + 1]);
          mx = math.max(mx, s);
          sq += s * s;
        }
        final score = mx * 1000 + sq * 1e-3;
        if (score < bestScore) {
          bestScore = score;
          bestCuts = List.of(cuts);
        }
        return;
      }
      for (var c = from; c <= toks.length - (k - 1 - cuts.length); c++) {
        cuts.add(c);
        search(cuts, c + 1);
        cuts.removeLast();
      }
    }

    search(<int>[], 1);
    final bounds = [0, ...bestCuts!, toks.length];
    return [
      for (var i = 0; i < k; i++) toks.sublist(bounds[i], bounds[i + 1]).join(' ')
    ];
  }

  static String _truncate(
      String s, double w, double size, double t, TitleFitSpec spec) {
    bool fits(String c) => _measure(c, spec).inkWidth(size, t) <= w;
    if (fits(s)) return s;
    // Longest whole-word prefix that fits with the ellipsis.
    final words = s.split(' ');
    String? wordCut;
    for (var n = words.length - 1; n >= 1; n--) {
      final cand = '${_trimPunct(words.take(n).join(' '))}…';
      if (fits(cand)) {
        wordCut = cand;
        break;
      }
    }
    // Longest character prefix that fits (binary search).
    var charCut = '…';
    final runes = s.runes.toList();
    var lo = 0, hi = runes.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      final cand = '${_trimPunct(String.fromCharCodes(runes.take(mid)))}…';
      if (fits(cand)) {
        lo = mid;
        charCut = cand;
      } else {
        hi = mid - 1;
      }
    }
    // A clean word break wins unless it throws away a lot more text.
    if (wordCut != null && wordCut.runes.length >= charCut.runes.length * 0.6) {
      return wordCut;
    }
    return charCut;
  }

  static String _trimPunct(String s) =>
      s.replaceAll(RegExp(r'[\s\p{P}]+$', unicode: true), '');

  static TitleFit _layout(String source, String text, List<String> lines,
      Size available, TitleFitSpec spec, double size, double t,
      TitleFitStage stage) {
    final ink = spec.ink;
    final ls = t * size;
    // Stack lines by their own ink extents.
    final tops = lines.map((l) => ink.topFor(l) * size).toList();
    final bottoms = lines.map((l) => ink.bottomFor(l) * size).toList();
    final gap = spec.lineGapEm * size;
    final baselines = <double>[];
    var y = 0.0;
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) y += bottoms[i - 1] + gap;
      y += tops[i];
      baselines.add(y);
    }
    final inkTop = baselines.first - tops.first;
    final inkBottom = baselines.last + bottoms.last;
    // Optical block: first cap top → last baseline.
    final capTop = baselines.first - ink.capTop * size;
    final optical = baselines.last - capTop;
    double offset;
    switch (spec.crossAlign) {
      case TitleAlign.start:
        offset = -inkTop;
      case TitleAlign.end:
        offset = available.height - inkBottom;
      case TitleAlign.center:
        offset = (available.height - optical) / 2 - capTop;
    }
    // Clamp so the full ink (accents, descenders) stays inside.
    if (inkTop + offset < 0) offset = -inkTop;
    if (inkBottom + offset > available.height) {
      offset = available.height - inkBottom;
    }
    final fitted = <FittedLine>[];
    for (var i = 0; i < lines.length; i++) {
      final width = _measure(lines[i], spec).inkWidth(size, t);
      final x = switch (spec.mainAlign) {
        TitleAlign.start => 0.0,
        TitleAlign.center => (available.width - width) / 2,
        TitleAlign.end => available.width - width,
      };
      final b = baselines[i] + offset;
      fitted.add(FittedLine(
        text: lines[i],
        baseline: b,
        inkBox: Rect.fromLTRB(x, b - tops[i], x + width, b + bottoms[i]),
      ));
    }
    return TitleFit._(
      source: source,
      text: text,
      spec: spec,
      available: available,
      fontSize: size,
      letterSpacing: ls,
      lines: List.unmodifiable(fitted),
      stage: stage,
    );
  }

  /// Clears the measurement caches (tests).
  @visibleForTesting
  static void clearCaches() {
    _runs.clear();
    _fits.clear();
  }

  /// Exposed for tests: the paragraph used to paint [line] of [fit].
  @visibleForTesting
  static ui.Paragraph paragraphFor(TitleFit fit, FittedLine line) =>
      LabelText.paragraph(line.text,
          family: fit.spec.fontFamily,
          size: fit.fontSize,
          weight: fit.spec.fontWeight,
          letterSpacing: fit.letterSpacing);
}
