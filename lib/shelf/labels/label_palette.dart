import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'label_rng.dart';

/// Colour helpers shared by the label painters.
class LabelColors {
  LabelColors._();

  /// Brand red (`AppColors.accent`), the NextCue studio colour.
  static const Color brandRed = Color(0xFFE60000);

  /// Bare board showing through where the print rubbed off.
  static const Color board = Color(0xFFE4DDCD);

  /// Default warm paper for labels and stickers.
  static const Color paper = Color(0xFFF2ECDF);

  /// Print black: process black on board is never #000.
  static const Color printBlack = Color(0xFF151413);

  static Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  static double luminance(Color c) => c.computeLuminance();

  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The more legible of [light] / [dark] on [bg].
  static Color on(Color bg, {Color light = paper, Color dark = printBlack}) =>
      contrast(bg, light) >= contrast(bg, dark) ? light : dark;

  static Color withAlpha(Color c, double a) => c.withValues(alpha: a);

  static Color hsl(double h, double s, double l) =>
      HSLColor.fromAHSL(1, h % 360, s.clamp(0.0, 1.0), l.clamp(0.0, 1.0))
          .toColor();

  /// Same hue, new lightness/saturation.
  static Color tone(Color c, {double? s, double? l}) {
    final h = HSLColor.fromColor(c);
    return HSLColor.fromAHSL(
      1,
      h.hue,
      (s ?? h.saturation).clamp(0.0, 1.0),
      (l ?? h.lightness).clamp(0.0, 1.0),
    ).toColor();
  }

  static double hueDistance(Color a, Color b) {
    final d = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();
    return d > 180 ? 360 - d : d;
  }
}

/// The colours one tape is printed with.
@immutable
class TapePalette {
  const TapePalette({
    required this.ink,
    required this.accent,
    required this.accent2,
    required this.paper,
    required this.fromPoster,
  });

  /// Deep, slightly tinted print black for dark grounds.
  final Color ink;

  /// The loudest colour (bands, boxes, blocks).
  final Color accent;

  /// A second colour for stripes and details.
  final Color accent2;

  /// Warm light ground.
  final Color paper;

  /// Whether the colours were sampled from the poster.
  final bool fromPoster;

  Color get muted => LabelColors.mix(ink, accent, 0.35);

  /// Readable text colour on [bg] using this palette's paper and ink.
  Color on(Color bg) => LabelColors.on(bg,
      light: paper, dark: LabelColors.mix(ink, LabelColors.printBlack, 0.5));

  @override
  bool operator ==(Object other) =>
      other is TapePalette &&
      other.ink == ink &&
      other.accent == accent &&
      other.accent2 == accent2 &&
      other.paper == paper &&
      other.fromPoster == fromPoster;

  @override
  int get hashCode => Object.hash(ink, accent, accent2, paper, fromPoster);

  /// Curated retro palettes for tapes without a poster.
  static const List<TapePalette> curated = [
    TapePalette(ink: Color(0xFF16110F), accent: Color(0xFFE60000), accent2: Color(0xFFF2B705), paper: Color(0xFFF1EADB), fromPoster: false),
    TapePalette(ink: Color(0xFF0F1E24), accent: Color(0xFFF26B1D), accent2: Color(0xFF1E9C9A), paper: Color(0xFFEFE8DA), fromPoster: false),
    TapePalette(ink: Color(0xFF0E1530), accent: Color(0xFF2D4BD8), accent2: Color(0xFFF2C14E), paper: Color(0xFFEEE9DD), fromPoster: false),
    TapePalette(ink: Color(0xFF0F1A12), accent: Color(0xFF2F8F4E), accent2: Color(0xFFE3B23C), paper: Color(0xFFECE6D6), fromPoster: false),
    TapePalette(ink: Color(0xFF140A1E), accent: Color(0xFFE5267A), accent2: Color(0xFF2EC4D6), paper: Color(0xFFF0E9E4), fromPoster: false),
    TapePalette(ink: Color(0xFF1E120B), accent: Color(0xFFD2691E), accent2: Color(0xFFE8B04B), paper: Color(0xFFF2E6CF), fromPoster: false),
    TapePalette(ink: Color(0xFF101820), accent: Color(0xFF3A8DDE), accent2: Color(0xFFE63A2E), paper: Color(0xFFEEF0EC), fromPoster: false),
    TapePalette(ink: Color(0xFF17150E), accent: Color(0xFFE0A526), accent2: Color(0xFF3B5BA5), paper: Color(0xFFF0EAD8), fromPoster: false),
    TapePalette(ink: Color(0xFF120F24), accent: Color(0xFF6B3FD6), accent2: Color(0xFFF28CB1), paper: Color(0xFFEEEAF0), fromPoster: false),
    TapePalette(ink: Color(0xFF0D1C1A), accent: Color(0xFFF25F5C), accent2: Color(0xFF4FB3A9), paper: Color(0xFFF3EDE3), fromPoster: false),
    TapePalette(ink: Color(0xFF121212), accent: Color(0xFFB5122B), accent2: Color(0xFF9AA3AD), paper: Color(0xFFECECEA), fromPoster: false),
    TapePalette(ink: Color(0xFF12160D), accent: Color(0xFF7DB83A), accent2: Color(0xFFF15A24), paper: Color(0xFFF0EEE2), fromPoster: false),
  ];

  static TapePalette curatedFor(String titleId) =>
      curated[LabelRng.forTitle(titleId, 'palette').nextInt(curated.length)];

  /// Palette for [titleId]: sampled from [poster] when present, otherwise
  /// one of the curated palettes. Sampling reads a tiny downscaled copy of
  /// the poster once per image (cached on the image).
  static Future<TapePalette> resolve(String titleId, ui.Image? poster) async {
    if (poster == null) return curatedFor(titleId);
    final swatch = await PosterSwatch.of(poster);
    return swatch.toPalette(titleId);
  }
}

/// Raw colours sampled from a poster; independent of the title id.
@immutable
class PosterSwatch {
  const PosterSwatch({
    required this.ink,
    required this.paper,
    this.accent,
    this.accent2,
    required this.average,
    this.detail = 0,
  });

  final Color ink;
  final Color paper;
  final Color? accent;
  final Color? accent2;
  final Color average;

  /// How busy the art is: mean luminance step between neighbouring
  /// samples of the 24×36 thumbnail (0 = flat, ~0.15+ = a busy collage).
  final double detail;

  static final Expando<Future<PosterSwatch>> _cache =
      Expando<Future<PosterSwatch>>('PosterSwatch');

  static const int sampleW = 24;
  static const int sampleH = 36;

  /// Samples [poster] (cached per image instance).
  static Future<PosterSwatch> of(ui.Image poster) =>
      _cache[poster] ??= _sample(poster);

  static Future<PosterSwatch> _sample(ui.Image poster) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImageRect(
      poster,
      Rect.fromLTWH(0, 0, poster.width.toDouble(), poster.height.toDouble()),
      const Rect.fromLTWH(0, 0, sampleW * 1.0, sampleH * 1.0),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final pic = rec.endRecording();
    final img = await pic.toImage(sampleW, sampleH);
    pic.dispose();
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (data == null) {
      return const PosterSwatch(
        ink: Color(0xFF151413),
        paper: LabelColors.paper,
        average: Color(0xFF555555),
      );
    }
    return fromRgba(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  /// Pure analysis of RGBA bytes of a [width]-wide thumbnail (exposed for
  /// tests).
  static PosterSwatch fromRgba(Uint8List px, {int width = sampleW}) {
    // Busy-ness: mean |ΔL| to the right and below neighbours.
    final count = px.length ~/ 4;
    final grid = List<double>.generate(count, (i) {
      final o = i * 4;
      return (0.2126 * px[o] + 0.7152 * px[o + 1] + 0.0722 * px[o + 2]) / 255.0;
    });
    var steps = 0.0, nSteps = 0;
    for (var i = 0; i < count; i++) {
      if ((i + 1) % width != 0 && i + 1 < count) {
        steps += (grid[i] - grid[i + 1]).abs();
        nSteps++;
      }
      if (i + width < count) {
        steps += (grid[i] - grid[i + width]).abs();
        nSteps++;
      }
    }
    final detail = nSteps == 0 ? 0.0 : steps / nSteps;
    const buckets = 18; // 20° hue buckets
    final bw = List<double>.filled(buckets, 0);
    final br = List<double>.filled(buckets, 0);
    final bg = List<double>.filled(buckets, 0);
    final bb = List<double>.filled(buckets, 0);
    final lum = <double>[];
    final cols = <int>[];
    double ar = 0, ag = 0, ab = 0;
    var n = 0;
    for (var i = 0; i + 3 < px.length; i += 4) {
      final a = px[i + 3];
      if (a < 128) continue;
      final r = px[i] / 255.0, g = px[i + 1] / 255.0, b = px[i + 2] / 255.0;
      ar += r;
      ag += g;
      ab += b;
      n++;
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      lum.add(l);
      cols.add(i);
      final d = mx - mn;
      if (mx <= 0 || d <= 0) continue;
      final sv = d / mx; // HSV saturation
      if (sv < 0.28 || mx < 0.22) continue;
      double h;
      if (mx == r) {
        h = 60 * (((g - b) / d) % 6);
      } else if (mx == g) {
        h = 60 * ((b - r) / d + 2);
      } else {
        h = 60 * ((r - g) / d + 4);
      }
      if (h < 0) h += 360;
      final k = (h / (360 / buckets)).floor() % buckets;
      final w = sv * sv * mx;
      bw[k] += w;
      br[k] += r * w;
      bg[k] += g * w;
      bb[k] += b * w;
    }
    if (n == 0) {
      return const PosterSwatch(
        ink: Color(0xFF151413),
        paper: LabelColors.paper,
        average: Color(0xFF555555),
      );
    }
    final average = Color.fromARGB(
        255, (ar / n * 255).round(), (ag / n * 255).round(), (ab / n * 255).round());

    // Darkest / lightest 15 % → ink / paper.
    final order = List<int>.generate(lum.length, (i) => i)
      ..sort((x, y) => lum[x].compareTo(lum[y]));
    final cut = math.max(1, (order.length * 0.15).round());
    Color avgOf(Iterable<int> idx) {
      double r = 0, g = 0, b = 0;
      var c = 0;
      for (final j in idx) {
        final o = cols[j];
        r += px[o];
        g += px[o + 1];
        b += px[o + 2];
        c++;
      }
      return Color.fromARGB(255, (r / c).round(), (g / c).round(), (b / c).round());
    }

    final darkAvg = avgOf(order.take(cut));
    final lightAvg = avgOf(order.skip(order.length - cut));

    // Smoothed hue histogram.
    final score = List<double>.generate(
        buckets,
        (i) =>
            bw[i] +
            0.5 * (bw[(i + buckets - 1) % buckets] + bw[(i + 1) % buckets]));
    var best = -1;
    for (var i = 0; i < buckets; i++) {
      if (best < 0 || score[i] > score[best]) best = i;
    }
    final total = bw.fold<double>(0, (s, v) => s + v);
    Color? bucketColor(int k) {
      // Average of the bucket and its neighbours.
      double w = 0, r = 0, g = 0, b = 0;
      for (final j in [k - 1, k, k + 1]) {
        final m = (j + buckets) % buckets;
        final f = j == k ? 1.0 : 0.5;
        w += bw[m] * f;
        r += br[m] * f;
        g += bg[m] * f;
        b += bb[m] * f;
      }
      if (w <= 0) return null;
      return Color.fromARGB(255, (r / w * 255).round().clamp(0, 255),
          (g / w * 255).round().clamp(0, 255), (b / w * 255).round().clamp(0, 255));
    }

    Color? accent;
    Color? accent2;
    // Needs a meaningful amount of colour (≈ 3 % of a fully saturated poster).
    if (best >= 0 && total > n * 0.03) {
      accent = bucketColor(best);
      var second = -1;
      for (var i = 0; i < buckets; i++) {
        var d = (i - best).abs();
        d = math.min(d, buckets - d);
        if (d < 3) continue; // ≥ 60° away
        if (second < 0 || score[i] > score[second]) second = i;
      }
      if (second >= 0 && score[second] > score[best] * 0.12) {
        accent2 = bucketColor(second);
      }
    }
    return PosterSwatch(
      ink: darkAvg,
      paper: lightAvg,
      accent: accent,
      accent2: accent2,
      average: average,
      detail: detail,
    );
  }

  /// Turns the raw swatch into print-ready colours. [titleId] only picks
  /// the treatment for near-monochrome art.
  TapePalette toPalette(String titleId) {
    final inkHsl = HSLColor.fromColor(ink);
    final printInk = HSLColor.fromAHSL(
            1, inkHsl.hue, math.min(inkHsl.saturation, 0.42), 0.085)
        .toColor();
    final paperHsl = HSLColor.fromColor(paper);
    final printPaper = LabelColors.mix(
      HSLColor.fromAHSL(1, paperHsl.hue, math.min(paperHsl.saturation, 0.3), 0.9)
          .toColor(),
      LabelColors.paper,
      0.65,
    );
    // Ink-on-board accents: keep the poster's hue, lift dull colours only
    // as far as print would (a moody poster stays moody).
    Color normAccent(Color c) {
      final h = HSLColor.fromColor(c);
      return HSLColor.fromAHSL(
        1,
        h.hue,
        (h.saturation * 1.15 + 0.08).clamp(0.38, 0.86),
        h.lightness.clamp(0.4, 0.56),
      ).toColor();
    }

    // Near-monochrome art: either the classic black / white / red
    // treatment or the poster's own tint, deepened (per title, so a shelf
    // of grey posters doesn't turn uniformly red).
    Color mono() {
      final h = HSLColor.fromColor(average);
      final tinted = h.saturation >= 0.06 && hashString(titleId) % 3 != 0;
      return tinted
          ? HSLColor.fromAHSL(1, h.hue, (h.saturation * 2.2).clamp(0.3, 0.5), 0.42).toColor()
          : const Color(0xFFC81D25);
    }

    final a1 = accent == null ? mono() : normAccent(accent!);
    Color a2;
    if (accent2 != null) {
      a2 = normAccent(accent2!);
    } else if (accent == null) {
      // Monochrome art: the second colour is the poster's own tint.
      final h = HSLColor.fromColor(average);
      a2 = HSLColor.fromAHSL(1, h.hue, (h.saturation * 1.4).clamp(0.08, 0.3), 0.74)
          .toColor();
    } else {
      // No second hue in the art: a pale tint of the lead keeps the tape
      // tonal instead of borrowing an unrelated colour.
      final h = HSLColor.fromColor(a1);
      a2 = HSLColor.fromAHSL(1, h.hue, (h.saturation * 0.6).clamp(0.2, 0.6), 0.78)
          .toColor();
    }
    return TapePalette(
      ink: printInk,
      accent: a1,
      accent2: a2,
      paper: printPaper,
      fromPoster: true,
    );
  }
}
