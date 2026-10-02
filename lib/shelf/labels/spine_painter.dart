import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'label_art.dart';
import 'label_palette.dart';
import 'label_print.dart';
import 'label_stickers.dart';
import 'label_text.dart';
import 'label_wear.dart';
import 'spine_style.dart';
import 'tape_label_data.dart';
import 'title_fitter.dart';

/// Paints a sleeve spine (28 × 190.5 mm). The *only* spine painter: both
/// the shelf atlas and the hero atlas call it, in the same design units,
/// so the hand-off from shelf to inspect view is seamless.
///
/// Orientation: the title reads top-to-bottom (rotated +90°), letter tops
/// towards the front cover.
class SpinePainter {
  SpinePainter._();

  // Layout grid (design units, 0.1 mm) for a 280 × 1905 spine.
  static const double _side = 34; // title margin from the long edges
  static const double _titleTop = 566;
  static const double _titleBottom = 1556;
  static const double _stickerY = 374;

  /// Title slot of the spine in local units (exposed for tests).
  static Rect titleZone(Size s) =>
      Rect.fromLTRB(_side, _titleTop, s.width - _side, _titleBottom);

  static TitleFitSpec antonSpec(SpineStyleSpec style, {double tracking = 0.015}) =>
      TitleFitSpec(
        maxFontSize: 170,
        minFontSize: 74,
        minFontSizeMultiLine: 56,
        trackingEm: tracking,
        minTrackingEm: -0.025,
        maxLines: 2,
        lineGapEm: 0.13,
        mainAlign: style.titleAlign,
      );

  static TitleFitSpec figtreeSpec(SpineStyleSpec style) => TitleFitSpec(
        fontFamily: LabelFonts.text,
        fontWeight: FontWeight.w800,
        ink: InkMetrics.figtree,
        maxFontSize: 92,
        minFontSize: 54,
        minFontSizeMultiLine: 44,
        trackingEm: 0.07,
        minTrackingEm: 0.0,
        maxLines: 2,
        lineGapEm: 0.24,
        mainAlign: style.titleAlign,
      );

  static final Paint _p = Paint();

  /// Paints the spine for [ctx] into [rect] (design units).
  static void paint(Canvas canvas, Rect rect, LabelContext ctx) {
    ctx.region('spine');
    canvas.save();
    // Hard region edges: complementary anti-aliased clips would leave a
    // half-transparent seam where two regions meet on a fractional pixel.
    canvas.clipRect(rect, doAntiAlias: false);
    canvas.translate(rect.left, rect.top);
    final s = rect.size;
    // Opaque base so anti-aliased shape edges never meet transparency.
    _p.color = ctx.palette.ink;
    canvas.drawRect(Offset.zero & s, _p);
    // Each style paints its print and reports the colours under the
    // sticker, so the sticker can stand out from them.
    final grounds = switch (ctx.style.kind) {
      SpineStyleKind.blackBand => _blackBand(canvas, s, ctx),
      SpineStyleKind.posterArt => _posterArt(canvas, s, ctx),
      SpineStyleKind.paperRules => _paperRules(canvas, s, ctx),
      SpineStyleKind.colourBlock => _colourBlock(canvas, s, ctx),
      SpineStyleKind.rentalStripe => _rentalStripe(canvas, s, ctx),
      SpineStyleKind.synthChrome => _synthChrome(canvas, s, ctx),
      SpineStyleKind.rainbow => _rainbow(canvas, s, ctx),
    };
    // Print grain over the whole spine.
    LabelPrint.grain(canvas, Offset.zero & s, ctx.grain, opacity: 0.13);
    _progressRule(canvas, s, ctx);
    LabelWear.paint(
      canvas,
      Offset.zero & s,
      titleId: ctx.data.titleId,
      salt: 'spine',
      level: ctx.wear,
      edges: const WearEdges(left: 1.5, right: 1.5, top: 1.1, bottom: 1.1),
    );
    LabelStickers.paintForState(
      canvas,
      Offset(s.width / 2 + ctx.style.stickerShift * 6,
          _stickerY + ctx.style.stickerShift * 30),
      ctx.data.state,
      isMovie: ctx.data.isMovie,
      tilt: ctx.style.stickerTilt,
      grain: ctx.grain,
      rng: ctx.rng('sticker'),
      grounds: grounds,
      recorder: ctx.recorder,
    );
    canvas.restore();
  }

  // ── shared pieces ─────────────────────────────────────────────────────

  /// Fits and paints the rotated title into [zone]; returns the fit.
  /// The spine's name: the clear logo when there is one (rotated to read
  /// top-to-bottom, aspect kept, one-colour if it would vanish on
  /// [ground]), otherwise the fitted title type.
  static void _title(Canvas canvas, LabelContext ctx, Rect zone,
      TitleFitSpec spec, Color color,
      {required Color ground}) {
    final logo = ctx.logo;
    if (logo != null) {
      _logo(canvas, ctx, zone, ground, spec.mainAlign);
      return;
    }
    _titleText(canvas, ctx, zone, spec, color);
  }

  /// Logo slot inside a title [zone]: a little air across the spine, and
  /// never longer than 70 % of the slot so it sits like printed art.
  static Rect _logo(Canvas canvas, LabelContext ctx, Rect zone, Color ground,
      TitleAlign align) {
    final logo = ctx.logo!;
    final across = zone.width * 0.94;
    final box = Rect.fromLTWH(zone.center.dx - across / 2, zone.top, across, zone.height);
    final maxLen = zone.height * 0.7;
    final ls = LabelArt.logoSize(logo, ctx.logoInfo);
    final scale = math.min(across / ls.height, maxLen / ls.width);
    return LabelArt.logo(canvas, logo, ctx.logoInfo, box,
        ground: ground,
        rotate: true,
        align: switch (align) {
          TitleAlign.start => -1,
          TitleAlign.center => 0,
          TitleAlign.end => 1,
        },
        maxScale: scale,
        recorder: ctx.recorder);
  }

  static TitleFit _titleText(Canvas canvas, LabelContext ctx, Rect zone,
      TitleFitSpec spec, Color color) {
    final fit = fitFor(ctx, zone, spec);
    canvas.save();
    canvas.translate(zone.right, zone.top);
    canvas.rotate(math.pi / 2);
    fit.paint(canvas, Offset.zero, color: color, recorder: ctx.recorder);
    canvas.restore();
    return fit;
  }

  /// The fit used for [zone] (main axis = zone height).
  static TitleFit fitFor(LabelContext ctx, Rect zone, TitleFitSpec spec) =>
      TitleFitter.fit(ctx.data.title, Size(zone.height, zone.width), spec);

  /// The studio mark in one of three treatments (per title), centred on
  /// [cy]: disc + wordmark, a boxed horizontal lockup, or a bare disc.
  static void _mark(Canvas canvas, LabelContext ctx, double cy,
      {Color disc = LabelColors.brandRed,
      Color glyph = const Color(0xFFFFFFFF),
      required Color word,
      double width = 280}) {
    switch (ctx.style.markStyle) {
      case 1:
        final box = Rect.fromCenter(center: Offset(width / 2, cy + 6), width: 206, height: 84);
        _p
          ..color = word
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5;
        canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)), _p);
        _p.style = PaintingStyle.fill;
        const d = 44.0;
        LabelPrint.studioMark(canvas, Offset(box.left + 18 + d / 2, box.center.dy), d,
            disc: disc, glyph: glyph);
        final tx = box.left + 18 + d + 14;
        final tw = box.right - 16 - tx;
        final a = FittedLabel.fit('NEXTCUE',
            family: LabelFonts.display,
            size: 34,
            maxWidth: tw,
            maxHeight: 30,
            trackingEm: 0.06,
            color: word,
            ink: InkMetrics.anton);
        final b = FittedLabel.fit('HOME VIDEO',
            family: LabelFonts.text,
            weight: FontWeight.w800,
            size: 12,
            maxWidth: tw,
            maxHeight: 12,
            trackingEm: 0.14,
            color: word,
            ink: InkMetrics.figtree);
        final total = a.capHeight + 9 + b.capHeight;
        final top = box.center.dy - total / 2;
        a.paint(canvas, tx, top + a.capHeight, recorder: ctx.recorder);
        b.paint(canvas, tx, top + total, recorder: ctx.recorder);
      case 2:
        LabelPrint.studioMark(canvas, Offset(width / 2, cy + 8), 100,
            disc: disc, glyph: glyph);
      default:
        LabelPrint.studioMark(canvas, Offset(width / 2, cy), 76,
            disc: disc,
            glyph: glyph,
            wordColor: word,
            wordWidth: 176,
            recorder: ctx.recorder);
    }
  }

  /// Year + catalogue number, centred, starting at [top].
  static void _yearBlock(Canvas canvas, LabelContext ctx, double top, Size s,
      Color color, {bool vhs = false, Color? vhsColor}) {
    var y = top;
    final year = ctx.data.year;
    if (year != null && year.isNotEmpty) {
      final f = FittedLabel.fit(year,
          family: LabelFonts.text,
          weight: FontWeight.w800,
          size: 52,
          maxWidth: s.width - 70,
          maxHeight: 52,
          trackingEm: 0.04,
          color: color,
          ink: InkMetrics.figtree);
      f.paint(canvas, (s.width - f.width) / 2, y + f.capHeight, recorder: ctx.recorder);
      y += f.capHeight + 22;
    }
    final cat = FittedLabel.fit(ctx.catalogueNo,
        family: LabelFonts.text,
        weight: FontWeight.w600,
        size: 20,
        maxWidth: s.width - 80,
        maxHeight: 20,
        trackingEm: 0.12,
        color: color.withValues(alpha: 0.78),
        ink: InkMetrics.figtree);
    cat.paint(canvas, (s.width - cat.width) / 2, y + cat.capHeight, recorder: ctx.recorder);
    y += cat.capHeight + 26;
    if (vhs) {
      LabelPrint.vhsLogo(
          canvas,
          Rect.fromCenter(center: Offset(s.width / 2, y + 26), width: 108, height: 50),
          vhsColor ?? color,
          recorder: ctx.recorder);
    }
  }

  static void _progressRule(Canvas canvas, Size s, LabelContext ctx) {
    final st = ctx.data.state;
    if (st.kind != TapeStateKind.watching) return;
    const x = 17.0, w = 9.0, top = 80.0;
    final bottom = s.height - 80;
    final bg = _groundAt(ctx);
    final track = LabelColors.on(bg).withValues(alpha: 0.22);
    var fill = LabelColors.brandRed;
    if (LabelColors.contrast(fill, bg) < 2.2) fill = LabelColors.on(bg);
    final p = st.progress.clamp(0.0, 1.0);
    _p.color = track;
    canvas.drawRect(Rect.fromLTRB(x, top, x + w, bottom), _p);
    _p.color = fill;
    canvas.drawRect(Rect.fromLTRB(x, top, x + w, top + (bottom - top) * p), _p);
    // Tick marks every 10 %.
    _p.color = LabelColors.on(bg).withValues(alpha: 0.5);
    for (var i = 1; i < 10; i++) {
      final y = top + (bottom - top) * i / 10;
      canvas.drawRect(Rect.fromLTRB(x + w, y - 1.2, x + w + 6, y + 1.2), _p);
    }
  }

  /// The dominant ground colour of the spine's long edge (for contrast).
  static Color _groundAt(LabelContext ctx) => switch (ctx.style.kind) {
        SpineStyleKind.paperRules => ctx.palette.paper,
        SpineStyleKind.rainbow =>
          ctx.style.variant < 2 ? ctx.palette.paper : ctx.palette.ink,
        SpineStyleKind.colourBlock => _blockColors(ctx)[1],
        SpineStyleKind.synthChrome => const Color(0xFF160A2C),
        SpineStyleKind.rentalStripe => _rentalGround(ctx),
        _ => ctx.palette.ink,
      };

  static Color _deepBlack(LabelContext ctx) =>
      LabelColors.mix(ctx.palette.ink, LabelColors.printBlack, 0.55);

  // ── 1. black band ─────────────────────────────────────────────────────
  static List<Color> _blackBand(Canvas canvas, Size s, LabelContext ctx) {
    final st = ctx.style;
    final bg = _deepBlack(ctx);
    _p.color = bg;
    canvas.drawRect(Offset.zero & s, _p);
    final lead = ctx.lead;
    final onLead = ctx.palette.on(lead);
    final paper = ctx.palette.paper;
    final bandH = 236 + st.band * 84;
    final bottomBand = st.variant == 1;
    if (!bottomBand) {
      _p.color = lead;
      canvas.drawRect(Rect.fromLTWH(0, 0, s.width, bandH), _p);
      if (st.variant >= 2) {
        _p.color = ctx.second;
        canvas.drawRect(Rect.fromLTWH(0, bandH + 16, s.width, 22), _p);
        if (st.variant == 3) {
          canvas.drawRect(Rect.fromLTWH(0, bandH + 46, s.width, 8), _p);
        }
      }
      _mark(canvas, ctx, 96,
          disc: onLead, glyph: lead, word: onLead);
      final titleColor = st.band2 > 0.6 &&
              LabelColors.contrast(lead, bg) > 4.5
          ? lead
          : paper;
      _title(canvas, ctx, titleZone(s), antonSpec(st), titleColor, ground: bg);
      _yearBlock(canvas, ctx, 1606, s, paper.withValues(alpha: 0.9), vhs: true);
      return [lead, bg, if (st.variant >= 2) ctx.second];
    } else {
      final top = s.height - bandH;
      _p.color = lead;
      canvas.drawRect(Rect.fromLTWH(0, top, s.width, bandH), _p);
      _p.color = ctx.second;
      canvas.drawRect(Rect.fromLTWH(0, top - 38, s.width, 20), _p);
      _mark(canvas, ctx, 96,
          disc: LabelColors.contrast(LabelColors.brandRed, bg) > 2.5
              ? LabelColors.brandRed
              : paper,
          word: paper);
      final zone = Rect.fromLTRB(_side, _titleTop, s.width - _side, top - 70);
      _title(canvas, ctx, zone, antonSpec(st), paper, ground: bg);
      _yearBlock(canvas, ctx, top + 60, s, onLead);
      return [bg];
    }
  }

  // ── 2. poster art ─────────────────────────────────────────────────────
  static List<Color> _posterArt(Canvas canvas, Size s, LabelContext ctx) {
    final st = ctx.style;
    final full = Offset.zero & s;
    // A vertical slice of the poster, else of the background art.
    final art = ctx.data.poster ?? ctx.data.background;
    if (art != null) {
      LabelPrint.cover(canvas, art, full, alignX: st.focusX, alignY: 0);
    } else {
      abstractArt(canvas, full, ctx, salt: 'spine-art');
    }
    final ink = ctx.palette.ink;
    // Dark gradient for the type; head and foot go (nearly) solid so the
    // poster's own type in the slice (billing, title) never fights the
    // studio mark, year and catalogue number.
    // A shader is modulated by the paint's alpha: reset it first.
    _p.color = const Color(0xFF000000);
    _p.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, s.height),
      [
        ink.withValues(alpha: 0.96),
        ink.withValues(alpha: 0.9),
        ink.withValues(alpha: 0.0),
        ink.withValues(alpha: 0.0),
        ink.withValues(alpha: 0.97),
        ink,
      ],
      const [0, 0.12, 0.3, 0.48, 0.76, 1],
    );
    canvas.drawRect(full, _p);
    _p.shader = null;
    final paper = ctx.palette.paper;
    final markTop = st.markAtTop;
    if (markTop) _mark(canvas, ctx, 96, word: paper);

    // Title in a colour box.
    final lead = ctx.lead;
    final textColor = ctx.palette.on(lead);
    const pad = 34.0, boxSide = 26.0;
    final zone = Rect.fromLTRB(
        boxSide + 20, _titleTop + pad, s.width - boxSide - 20, _titleBottom - pad);
    final logo = ctx.logo;
    final TitleFit? fit;
    final double contentLen;
    if (logo != null) {
      // Logo length once fitted across the box (≤ 70 % of the slot).
      final ls = LabelArt.logoSize(logo, ctx.logoInfo);
      final sc = math.min(zone.width * 0.94 / ls.height, zone.height * 0.7 / ls.width);
      contentLen = ls.width * sc;
      fit = null;
    } else {
      fit = fitFor(ctx, zone, antonSpec(st, tracking: 0.025));
      contentLen = fit.inkBounds.width;
    }
    // Box along the spine, in spine coordinates.
    final boxLen = contentLen + pad * 2;
    double boxTop;
    switch (st.titleAlign) {
      case TitleAlign.start:
        boxTop = _titleTop;
      case TitleAlign.end:
        boxTop = _titleBottom - boxLen;
      case TitleAlign.center:
        boxTop = _titleTop + (_titleBottom - _titleTop - boxLen) / 2;
    }
    final box = Rect.fromLTRB(boxSide, boxTop, s.width - boxSide, boxTop + boxLen);
    _p.color = lead;
    canvas.drawRect(box, _p);
    // Thin keyline inset in the text colour.
    _p
      ..color = textColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(box.deflate(9), _p);
    _p.style = PaintingStyle.fill;
    if (fit == null) {
      LabelArt.logo(canvas, logo!, ctx.logoInfo,
          Rect.fromLTWH(zone.left, boxTop + pad, zone.width, contentLen),
          ground: lead, rotate: true, recorder: ctx.recorder);
    } else {
      canvas.save();
      // Rotated frame: x along the spine from box top + pad - ink left.
      canvas.translate(zone.right, boxTop + pad - fit.inkBounds.left);
      canvas.rotate(math.pi / 2);
      fit.paint(canvas, Offset.zero, color: textColor, recorder: ctx.recorder);
      canvas.restore();
    }

    if (markTop) {
      _yearBlock(canvas, ctx, 1630, s, paper, vhs: true);
    } else {
      _mark(canvas, ctx, 1660, word: paper);
      final year = ctx.data.year;
      if (year != null) {
        final f = FittedLabel.fit(year,
            family: LabelFonts.text,
            weight: FontWeight.w800,
            size: 44,
            maxWidth: s.width - 80,
            maxHeight: 44,
            trackingEm: 0.06,
            color: paper,
            ink: InkMetrics.figtree);
        f.paint(canvas, (s.width - f.width) / 2, 1800 + f.capHeight,
            recorder: ctx.recorder);
      }
    }
    return [ctx.palette.accent, ink];
  }

  /// Designed stand-in for missing poster art: duotone gradient, a big
  /// sun disc with cut lines and a fan of rays — never a grey box.
  static void abstractArt(Canvas canvas, Rect r, LabelContext ctx,
      {required String salt}) {
    final rng = ctx.rng(salt);
    final pal = ctx.palette;
    canvas.save();
    canvas.clipRect(r);
    // A shader is modulated by the paint's alpha: reset it first.
    _p.color = const Color(0xFF000000);
    _p.shader = ui.Gradient.linear(
      r.topCenter,
      r.bottomCenter,
      [
        LabelColors.mix(pal.ink, pal.accent, 0.25),
        LabelColors.mix(pal.ink, pal.accent, 0.75),
        pal.accent,
      ],
      const [0, 0.6, 1],
    );
    canvas.drawRect(r, _p);
    _p.shader = null;
    // Rays from a low vanishing point.
    final vp = Offset(r.left + r.width * rng.range(0.2, 0.8), r.top + r.height * 0.72);
    _p.color = pal.accent2.withValues(alpha: 0.16);
    const rays = 14;
    for (var i = 0; i < rays; i += 2) {
      final a0 = -math.pi + i * math.pi / rays;
      final a1 = a0 + math.pi / rays;
      final far = r.longestSide * 2;
      canvas.drawPath(
          Path()
            ..moveTo(vp.dx, vp.dy)
            ..lineTo(vp.dx + math.cos(a0) * far, vp.dy + math.sin(a0) * far)
            ..lineTo(vp.dx + math.cos(a1) * far, vp.dy + math.sin(a1) * far)
            ..close(),
          _p);
    }
    // Sun with cut lines.
    final rad = r.width * rng.range(0.42, 0.7);
    final c = Offset(vp.dx, vp.dy - rad * 0.15);
    // A shader is modulated by the paint's alpha: reset it first.
    _p.color = const Color(0xFF000000);
    _p.shader = ui.Gradient.linear(
      c - Offset(0, rad),
      c + Offset(0, rad),
      [pal.accent2, LabelColors.mix(pal.accent2, pal.accent, 0.6)],
    );
    canvas.drawCircle(c, rad, _p);
    _p.shader = null;
    _p.color = LabelColors.mix(pal.ink, pal.accent, 0.7);
    for (var i = 0; i < 6; i++) {
      final y = c.dy + rad * (0.05 + i * 0.17);
      final h = rad * (0.025 + i * 0.018);
      canvas.drawRect(Rect.fromLTRB(c.dx - rad, y, c.dx + rad, y + h), _p);
    }
    canvas.restore();
  }

  // ── 3. paper + rules ──────────────────────────────────────────────────
  static List<Color> _paperRules(Canvas canvas, Size s, LabelContext ctx) {
    final st = ctx.style;
    final paper = LabelColors.mix(ctx.palette.paper, LabelColors.paper, 0.4);
    _p.color = paper;
    canvas.drawRect(Offset.zero & s, _p);
    final inkC = LabelColors.mix(ctx.palette.ink, LabelColors.printBlack, 0.6);
    final lead = ctx.lead;
    const ruleTop = 512.0, ruleBottom = 1610.0;
    void rule(double y, double t) {
      _p.color = inkC;
      canvas.drawRect(Rect.fromLTRB(24, y - t / 2, s.width - 24, y + t / 2), _p);
    }

    rule(ruleTop, 4.5);
    rule(ruleBottom, 4.5);
    if (st.variant.isOdd) {
      rule(ruleTop + 13, 2);
      rule(ruleBottom - 13, 2);
    }
    // Accent: a solid square or a short bar.
    _p.color = lead;
    if (st.variant < 2) {
      canvas.drawRect(
          Rect.fromCenter(center: Offset(s.width / 2, ruleBottom + 62), width: 50, height: 50),
          _p);
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, s.width, 22), _p);
      canvas.drawRect(Rect.fromLTWH(0, s.height - 22, s.width, 22), _p);
    }
    _mark(canvas, ctx, 112, word: inkC);
    _title(canvas, ctx, Rect.fromLTRB(_side + 6, _titleTop, s.width - _side - 6, 1556),
        figtreeSpec(st), inkC,
        ground: paper);
    _yearBlock(canvas, ctx, st.variant < 2 ? 1722 : 1680, s, inkC);
    return [paper];
  }

  // ── 4. colour blocks ──────────────────────────────────────────────────
  static List<Color> _blockColors(LabelContext ctx) {
    final pal = ctx.palette;
    final ink = _deepBlack(ctx);
    return switch (ctx.style.variant) {
      0 => [ctx.lead, ink, ctx.second],
      1 => [ink, ctx.lead, ink],
      2 => [ctx.second, ctx.lead, ink],
      _ => [pal.paper, ink, ctx.lead],
    };
  }

  static List<Color> _colourBlock(Canvas canvas, Size s, LabelContext ctx) {
    final st = ctx.style;
    final cols = _blockColors(ctx);
    final yA = 262 + st.band * 70;
    final yB = 1592 - st.band2 * 40;
    final slant = st.band2 > 0.5 ? 46.0 : 0.0;
    _p.color = cols[1];
    canvas.drawRect(Offset.zero & s, _p);
    _p.color = cols[0];
    canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width, yA - slant)
          ..lineTo(0, yA + slant)
          ..close(),
        _p);
    _p.color = cols[2];
    canvas.drawPath(
        Path()
          ..moveTo(0, yB + slant)
          ..lineTo(s.width, yB - slant)
          ..lineTo(s.width, s.height)
          ..lineTo(0, s.height)
          ..close(),
        _p);
    // Hairline separators in paper.
    if (st.variant != 3) {
      _p
        ..color = ctx.palette.paper
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5;
      canvas.drawLine(Offset(0, yA + slant + 14), Offset(s.width, yA - slant + 14), _p);
      canvas.drawLine(Offset(0, yB + slant - 14), Offset(s.width, yB - slant - 14), _p);
      _p.style = PaintingStyle.fill;
    }
    final onA = ctx.palette.on(cols[0]);
    final markDisc = LabelColors.hueDistance(cols[0], LabelColors.brandRed) < 25 &&
            HSLColor.fromColor(cols[0]).saturation > 0.4
        ? onA
        : LabelColors.brandRed;
    _mark(canvas, ctx, 100,
        disc: markDisc, glyph: markDisc == onA ? cols[0] : const Color(0xFFFFFFFF), word: onA);
    final onB = ctx.palette.on(cols[1]);
    final zone = Rect.fromLTRB(_side, math.max(_titleTop, yA + slant + 40),
        s.width - _side, math.min(_titleBottom, yB - slant - 50));
    _title(canvas, ctx, zone, antonSpec(st, tracking: 0.02), onB, ground: cols[1]);
    _yearBlock(canvas, ctx, yB + slant + 50, s, ctx.palette.on(cols[2]));
    return [cols[0], cols[1]];
  }

  // ── 5. rental stripes ─────────────────────────────────────────────────
  static Color _rentalGround(LabelContext ctx) => ctx.style.variant.isEven
      ? _deepBlack(ctx)
      : LabelColors.tone(ctx.lead, s: 0.55, l: 0.15);

  static List<Color> _rentalStripe(Canvas canvas, Size s, LabelContext ctx) {
    final st = ctx.style;
    final ground = _rentalGround(ctx);
    _p.color = ground;
    canvas.drawRect(Offset.zero & s, _p);
    final headerH = 262 + st.band * 40;
    final stripeColors = st.variant < 2
        ? [ctx.lead, ctx.palette.paper]
        : [ctx.lead, ctx.second, ground];
    LabelPrint.diagonalStripes(canvas, Rect.fromLTWH(0, 0, s.width, headerH),
        stripeColors, 30 + st.band2 * 10);
    // Store tag over the stripes.
    final tag = Rect.fromCenter(center: Offset(s.width / 2, 124), width: 214, height: 104);
    _p.color = LabelColors.paper;
    canvas.drawRect(tag, _p);
    _p
      ..color = LabelColors.printBlack
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(tag.deflate(7), _p);
    _p.style = PaintingStyle.fill;
    final club = FittedLabel.fit('VIDEO CLUB',
        family: LabelFonts.text,
        weight: FontWeight.w800,
        size: 16,
        maxWidth: tag.width - 40,
        maxHeight: 16,
        trackingEm: 0.2,
        color: LabelColors.printBlack,
        ink: InkMetrics.figtree);
    club.paint(canvas, tag.center.dx - club.width / 2, tag.top + 20 + club.capHeight,
        recorder: ctx.recorder);
    final no = FittedLabel.fit('Nº ${st.catalogue}',
        family: LabelFonts.display,
        size: 46,
        maxWidth: tag.width - 40,
        maxHeight: 44,
        trackingEm: 0.04,
        color: LabelColors.brandRed,
        ink: InkMetrics.anton);
    no.paint(canvas, tag.center.dx - no.width / 2, tag.bottom - 18, recorder: ctx.recorder);
    // Thin rule under the header.
    _p.color = ctx.lead;
    canvas.drawRect(Rect.fromLTWH(0, headerH + 14, s.width, 7), _p);
    final paper = ctx.palette.paper;
    _title(canvas, ctx, titleZone(s), antonSpec(st, tracking: 0.03), paper,
        ground: ground);
    // Foot: mark + year, small stripes at the very bottom.
    _mark(canvas, ctx, 1650, word: paper);
    final year = ctx.data.year;
    if (year != null) {
      final f = FittedLabel.fit(year,
          family: LabelFonts.text,
          weight: FontWeight.w800,
          size: 44,
          maxWidth: s.width - 80,
          maxHeight: 44,
          trackingEm: 0.06,
          color: paper,
          ink: InkMetrics.figtree);
      f.paint(canvas, (s.width - f.width) / 2, 1790 + f.capHeight, recorder: ctx.recorder);
    }
    LabelPrint.diagonalStripes(canvas, Rect.fromLTWH(0, s.height - 44, s.width, 44),
        stripeColors, 22);
    return [ground, ...stripeColors];
  }

  // ── 6. synth chrome ───────────────────────────────────────────────────
  static const List<(Color, Color, List<Color>)> _synthSkies = [
    (Color(0xFF0B0620), Color(0xFF2A0F45), [Color(0xFFFFE066), Color(0xFFFF7A45), Color(0xFFFF2E88)]),
    (Color(0xFF041420), Color(0xFF0E3346), [Color(0xFFFFF3A0), Color(0xFF52E5D6), Color(0xFF2E7BFF)]),
    (Color(0xFF16040C), Color(0xFF3E0B26), [Color(0xFFFFD36B), Color(0xFFFF5C5C), Color(0xFFB0198F)]),
    (Color(0xFF07061A), Color(0xFF1E1650), [Color(0xFFFFB3E6), Color(0xFFB36BFF), Color(0xFF3D5CFF)]),
  ];

  static List<Color> _synthChrome(Canvas canvas, Size s, LabelContext ctx) {
    final st = ctx.style;
    final (top, bottom, sun) = _synthSkies[st.variant];
    final full = Offset.zero & s;
    // A shader is modulated by the paint's alpha: reset it first.
    _p.color = const Color(0xFF000000);
    _p.shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height), [top, bottom]);
    canvas.drawRect(full, _p);
    _p.shader = null;
    // Striped sun band across the head.
    final c = Offset(s.width / 2, 250);
    final rad = s.width * 0.47;
    // A shader is modulated by the paint's alpha: reset it first.
    _p.color = const Color(0xFF000000);
    _p.shader = ui.Gradient.linear(
        c - Offset(0, rad), c + Offset(0, rad), sun, const [0, 0.5, 1]);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, s.width, c.dy + rad * 0.78));
    canvas.drawCircle(c, rad, _p);
    canvas.restore();
    _p.shader = null;
    _p.color = top;
    for (var i = 0; i < 6; i++) {
      final y = c.dy + rad * (-0.05 + i * 0.15);
      final h = rad * (0.03 + i * 0.022);
      canvas.drawRect(Rect.fromLTRB(0, y, s.width, y + h), _p);
    }
    // Horizon line.
    _p.color = sun.last;
    canvas.drawRect(Rect.fromLTWH(0, c.dy + rad * 0.82, s.width, 5), _p);

    // Chrome title (or the show's own logo, printed on the night sky).
    final zone = Rect.fromLTRB(_side, _titleTop, s.width - _side, 1500);
    if (ctx.logo != null) {
      _logo(canvas, ctx, zone, LabelColors.mix(top, bottom, 0.4), st.titleAlign);
    } else {
      _chromeTitle(canvas, ctx, zone, st, top);
    }
    _synthFoot(canvas, s, ctx, sun, top);
    return [top, sun[1], sun.last];
  }

  static void _chromeTitle(
      Canvas canvas, LabelContext ctx, Rect zone, SpineStyleSpec st, Color top) {
    final fit = fitFor(ctx, zone, antonSpec(st, tracking: 0.03));
    canvas.save();
    canvas.translate(zone.right, zone.top);
    canvas.rotate(math.pi / 2);
    // Dark keyline under the fill.
    fit.paint(canvas, Offset.zero,
        color: LabelColors.mix(top, LabelColors.printBlack, 0.5), strokeWidth: 9);
    final bounds = fit.inkBounds.inflate(6);
    canvas.saveLayer(bounds, Paint());
    fit.paint(canvas, Offset.zero, color: const Color(0xFFFFFFFF), recorder: ctx.recorder);
    for (final line in fit.lines) {
      final capTop = line.baseline - fit.spec.ink.capTop * fit.fontSize;
      final r = Rect.fromLTRB(bounds.left, line.inkBox.top - 2, bounds.right, line.inkBox.bottom + 2);
      _p
        ..blendMode = BlendMode.srcIn
        ..color = const Color(0xFF000000)
        ..shader = ui.Gradient.linear(
          Offset(0, capTop),
          Offset(0, line.baseline),
          const [
            Color(0xFFFFFFFF),
            Color(0xFF9FD0F5),
            Color(0xFF3B6FA8),
            Color(0xFF1B1530),
            Color(0xFFC9734A),
            Color(0xFFF6C27A),
            Color(0xFFFFF4DA),
          ],
          const [0, 0.32, 0.5, 0.52, 0.6, 0.82, 1],
        );
      canvas.drawRect(r, _p);
    }
    _p
      ..blendMode = BlendMode.srcOver
      ..shader = null;
    canvas.restore();
    canvas.restore();
  }

  static void _synthFoot(
      Canvas canvas, Size s, LabelContext ctx, List<Color> sun, Color top) {
    // Neon grid floor at the foot.
    const gTop = 1640.0;
    final grid = Rect.fromLTRB(0, gTop, s.width, s.height);
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = sun.last.withValues(alpha: 0.85);
    canvas.save();
    canvas.clipRect(grid);
    for (var i = 0; i < 9; i++) {
      final t = i / 8;
      final y = gTop + (s.height - gTop) * t * t;
      canvas.drawLine(Offset(0, y), Offset(s.width, y), _p);
    }
    final vp = Offset(s.width / 2, gTop - 120);
    for (var i = -6; i <= 6; i++) {
      final x = s.width / 2 + i * 70.0;
      final dir = Offset(x, s.height) - vp;
      final start = vp + dir * ((gTop - vp.dy) / dir.dy);
      canvas.drawLine(start, Offset(x, s.height), _p);
    }
    canvas.restore();
    _p.style = PaintingStyle.fill;
    _mark(canvas, ctx, 1548,
        disc: sun.last, glyph: top, word: sun.first);
  }

  // ── 7. rainbow stripes ────────────────────────────────────────────────
  static const List<Color> _retroRamp = [
    Color(0xFFD9382C),
    Color(0xFFEE7F2D),
    Color(0xFFF2C14A),
    Color(0xFF4F9D53),
    Color(0xFF2F6CB0),
  ];

  static List<Color> _rainbow(Canvas canvas, Size s, LabelContext ctx) {
    final st = ctx.style;
    final light = st.variant < 2;
    final ground = light ? ctx.palette.paper : _deepBlack(ctx);
    _p.color = ground;
    canvas.drawRect(Offset.zero & s, _p);
    final ramp = st.variant.isEven
        ? _retroRamp
        : List<Color>.generate(5, (i) {
            final t = i / 4;
            return LabelColors.mix(ctx.palette.accent, ctx.palette.accent2, t);
          });
    void stripes(double top) {
      const h = 19.0, gap = 7.0;
      for (var i = 0; i < ramp.length; i++) {
        _p.color = ramp[i];
        canvas.drawRect(Rect.fromLTWH(0, top + i * (h + gap), s.width, h), _p);
      }
    }

    stripes(st.markAtTop ? 214 : 56);
    stripes(1588);
    final inkC = ctx.palette.on(ground);
    if (st.markAtTop) {
      _mark(canvas, ctx, 92, word: inkC);
    } else {
      _yearBlock(canvas, ctx, 214, s, inkC);
    }
    _title(canvas, ctx, titleZone(s), antonSpec(st, tracking: 0.02), inkC,
        ground: ground);
    if (st.markAtTop) {
      _yearBlock(canvas, ctx, 1745, s, inkC);
    } else {
      _mark(canvas, ctx, 1752, word: inkC);
    }
    return [ground, if (st.markAtTop) ...ramp];
  }
}
