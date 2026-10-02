import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'label_art.dart';
import 'label_palette.dart';
import 'label_print.dart';
import 'label_text.dart';
import 'label_wear.dart';
import 'spine_style.dart';
import 'title_fitter.dart';

/// Paints the sleeve front (107 × 190.5 mm). Its left edge is the spine
/// fold; the shelf atlas' `front_strip` is the left 20 mm of exactly this
/// painting.
class FrontCoverPainter {
  FrontCoverPainter._();

  static const double bandH = 64;
  static const double stripH = 176;

  static final Paint _p = Paint();

  /// The front's house-style variant for [ctx] (deterministic per title):
  /// band colour, strip colour, which side the VHS block sits on, and
  /// whether the art is framed in paper with a stripe along the fold. The
  /// shelf sees the left 20 mm, so this is what keeps a row of fronts from
  /// looking cloned.
  static _FrontLook _lookFor(LabelContext ctx) {
    final r = ctx.rng('front-look');
    final look = r.nextInt(4);
    final lead = ctx.lead;
    return switch (look) {
      0 => const _FrontLook(
          band: LabelColors.printBlack,
          bandText: LabelColors.paper,
          strip: LabelColors.printBlack,
          stripText: LabelColors.paper,
          vhsLeft: true,
          framed: false),
      1 => const _FrontLook(
          band: LabelColors.brandRed,
          bandText: Color(0xFFFFFFFF),
          strip: LabelColors.printBlack,
          stripText: LabelColors.paper,
          vhsLeft: false,
          framed: false),
      2 => _FrontLook(
          band: LabelColors.printBlack,
          bandText: LabelColors.paper,
          strip: lead,
          stripText: ctx.palette.on(lead),
          vhsLeft: true,
          framed: false),
      _ => const _FrontLook(
          band: LabelColors.paper,
          bandText: LabelColors.printBlack,
          strip: LabelColors.paper,
          stripText: LabelColors.printBlack,
          vhsLeft: false,
          framed: true),
    };
  }

  static void paint(Canvas canvas, Rect rect, LabelContext ctx) {
    ctx.region('front');
    canvas.save();
    // Hard region edges: complementary anti-aliased clips would leave a
    // half-transparent seam where two regions meet on a fractional pixel.
    canvas.clipRect(rect, doAntiAlias: false);
    canvas.translate(rect.left, rect.top);
    final s = rect.size;
    final look = _lookFor(ctx);
    // Opaque base: anti-aliased edges between the bands and the art must
    // land on board, not on transparency.
    _p.color = look.band;
    canvas.drawRect(Offset.zero & s, _p);
    var art = Rect.fromLTRB(0, bandH, s.width, s.height - stripH);
    if (look.framed) {
      // Paper frame with a lead-colour stripe running down the fold.
      _p.color = LabelColors.paper;
      canvas.drawRect(art, _p);
      _p.color = ctx.lead;
      canvas.drawRect(Rect.fromLTWH(0, art.top, 74, art.height), _p);
      art = Rect.fromLTRB(74 + 26, art.top + 26, s.width - 26, art.bottom - 26);
    }
    final poster = ctx.data.poster;
    final background = ctx.data.background;
    if (poster != null) {
      // The TVDB poster, printed: cover-fit (top-biased), graded, grain
      // and vignette. Posters carry their own title treatment, so the clear
      // logo goes on only when the art is busy enough to swallow it.
      LabelPrint.cover(canvas, poster, art, alignY: -0.6);
      LabelPrint.vignette(canvas, art, strength: 0.17);
      if (ctx.logo != null && ctx.posterDetail >= busyPoster) {
        _logoOverArt(canvas, art, ctx);
      }
    } else if (background != null) {
      backgroundCover(canvas, art, ctx, background);
    } else {
      typographicCover(canvas, art, ctx);
    }
    _studioBand(canvas, s, ctx, look);
    _bottomStrip(canvas, s, ctx, look);
    LabelPrint.grain(canvas, Offset.zero & s, ctx.grain, opacity: 0.15);
    LabelWear.paint(canvas, Offset.zero & s,
        titleId: ctx.data.titleId,
        salt: 'front',
        level: ctx.wear,
        edges: const WearEdges(left: 1.5, top: 1, right: 0.8, bottom: 1));
    canvas.restore();
  }

  /// [PosterSwatch.detail] above which a poster counts as busy (a collage,
  /// a crowd): only then does the clear logo go over it. Calibrated on the
  /// test art: clean key-art posters measure 0.028-0.053, a 5x7 collage
  /// 0.074.
  static const double busyPoster = 0.065;

  /// The clear logo in the lower third of [art] on an ink scrim, one-colour
  /// if it would vanish into it.
  static void _logoOverArt(Canvas canvas, Rect art, LabelContext ctx) {
    final ink = LabelColors.mix(ctx.palette.ink, LabelColors.printBlack, 0.4);
    LabelArt.scrim(canvas, art, ink, from: 0.5, strength: 0.88);
    final box = Rect.fromLTRB(art.left + art.width * 0.09, art.top + art.height * 0.7,
        art.right - art.width * 0.09, art.bottom - art.height * 0.06);
    LabelArt.logo(canvas, ctx.logo!, ctx.logoInfo, box,
        ground: ink, recorder: ctx.recorder);
  }

  /// No poster but TVDB background art: a portrait crop of the fanart,
  /// printed, with the logo (or set title) over an ink scrim, year and
  /// genres underneath — a cover, not a screenshot.
  static void backgroundCover(
      Canvas canvas, Rect art, LabelContext ctx, ui.Image background) {
    canvas.save();
    canvas.clipRect(art);
    LabelArt.photo(canvas, background, art,
        alignX: ctx.style.focusX * 0.5, alignY: -0.2, vignette: 0.2);
    final ink = LabelColors.mix(ctx.palette.ink, LabelColors.printBlack, 0.4);
    LabelArt.scrim(canvas, art, ink, from: 0.42, strength: 0.92);
    const m = 70.0;
    final paper = ctx.palette.paper;
    // Meta line at the foot.
    final meta = [
      if (ctx.data.year != null) ctx.data.year!,
      ...ctx.data.genres.take(2).map((g) => g.toUpperCase()),
    ].join('  ·  ');
    var bottom = art.bottom - m;
    if (meta.isNotEmpty) {
      final g = FittedLabel.fit(meta,
          family: LabelFonts.text,
          weight: FontWeight.w700,
          size: 26,
          maxWidth: art.width - 2 * m,
          maxHeight: 26,
          trackingEm: 0.22,
          color: paper.withValues(alpha: 0.88),
          ink: InkMetrics.figtree);
      g.paint(canvas, art.left + m, bottom, recorder: ctx.recorder);
      bottom -= g.capHeight + 40;
    }
    _p.color = ctx.lead;
    canvas.drawRect(Rect.fromLTWH(art.left + m, bottom - 12, 150, 12), _p);
    bottom -= 52;
    final nameBox = Rect.fromLTRB(art.left + m, bottom - art.height * 0.26, art.right - m, bottom);
    if (ctx.logo != null) {
      LabelArt.logo(canvas, ctx.logo!, ctx.logoInfo, nameBox,
          ground: ink, align: -1, recorder: ctx.recorder);
    } else {
      const spec = TitleFitSpec(
        maxFontSize: 200,
        minFontSize: 110,
        minFontSizeMultiLine: 76,
        trackingEm: 0.005,
        maxLines: 3,
        lineGapEm: 0.1,
        mainAlign: TitleAlign.start,
        crossAlign: TitleAlign.end,
      );
      final fit = TitleFitter.fit(ctx.data.title, nameBox.size, spec);
      fit.paint(canvas, nameBox.topLeft, color: paper, recorder: ctx.recorder);
    }
    canvas.restore();
  }

  static void _studioBand(Canvas canvas, Size s, LabelContext ctx, _FrontLook look) {
    final band = Rect.fromLTWH(0, 0, s.width, bandH);
    _p.color = look.band;
    canvas.drawRect(band, _p);
    final redBand = look.band == LabelColors.brandRed;
    // Mark + wordmark, centred as a group.
    final label = FittedLabel.fit('NEXTCUE  HOME  VIDEO',
        family: LabelFonts.text,
        weight: FontWeight.w800,
        size: 23,
        maxWidth: s.width - 220,
        maxHeight: 23,
        trackingEm: 0.32,
        color: look.bandText,
        ink: InkMetrics.figtree);
    const d = 38.0;
    final groupW = d + 16 + label.width;
    final x0 = (s.width - groupW) / 2;
    LabelPrint.studioMark(canvas, Offset(x0 + d / 2, bandH / 2), d,
        disc: redBand ? const Color(0xFFFFFFFF) : LabelColors.brandRed,
        glyph: redBand ? LabelColors.brandRed : const Color(0xFFFFFFFF));
    label.paint(canvas, x0 + d + 16, bandH / 2 + label.capHeight / 2,
        recorder: ctx.recorder);
    // Keyline under the band.
    _p.color = look.framed ? LabelColors.printBlack : ctx.lead;
    canvas.drawRect(Rect.fromLTWH(0, bandH, s.width, look.framed ? 3 : 5), _p);
  }

  static void _bottomStrip(Canvas canvas, Size s, LabelContext ctx, _FrontLook look) {
    final top = s.height - stripH;
    final strip = Rect.fromLTWH(0, top, s.width, stripH);
    _p.color = look.strip;
    canvas.drawRect(strip, _p);
    final ink = look.stripText;
    _p.color = look.framed
        ? LabelColors.printBlack
        : (look.strip == ctx.lead ? LabelColors.printBlack : ctx.lead);
    canvas.drawRect(Rect.fromLTWH(0, top, s.width, look.framed ? 3 : 6), _p);
    // Rating box on the right.
    final rating = Rect.fromLTWH(s.width - 46 - 118, top + 34, 118, 112);
    // The box is printed in the strip's text colour, knocked out of it.
    final ratingInk = look.strip;
    _p.color = ink;
    canvas.drawRect(rating, _p);
    final rLbl = FittedLabel.fit('RATED',
        family: LabelFonts.text,
        weight: FontWeight.w800,
        size: 14,
        maxWidth: rating.width - 20,
        maxHeight: 14,
        trackingEm: 0.25,
        color: ratingInk,
        ink: InkMetrics.figtree);
    rLbl.paint(canvas, rating.center.dx - rLbl.width / 2, rating.top + 12 + rLbl.capHeight,
        recorder: ctx.recorder);
    final nr = FittedLabel.fit('NR',
        family: LabelFonts.display,
        size: 70,
        maxWidth: rating.width - 26,
        maxHeight: 62,
        color: ratingInk,
        ink: InkMetrics.anton);
    nr.paint(canvas, rating.center.dx - nr.width / 2, rating.bottom - 12,
        recorder: ctx.recorder);
    // VHS block: left (inside the shelf's front strip) or next to the rating.
    final vhs = look.vhsLeft
        ? Rect.fromLTWH(46, top + 46, 136, 64)
        : Rect.fromLTWH(rating.left - 36 - 136, top + 46, 136, 64);
    LabelPrint.vhsLogo(canvas, vhs, ink, recorder: ctx.recorder);
    final hifi = FittedLabel.fit('HI-FI',
        family: LabelFonts.text,
        weight: FontWeight.w800,
        size: 17,
        maxWidth: 136,
        maxHeight: 17,
        trackingEm: 0.3,
        color: ink,
        ink: InkMetrics.figtree);
    hifi.paint(canvas, vhs.center.dx - hifi.width / 2, vhs.bottom + 18 + hifi.capHeight,
        recorder: ctx.recorder);
    // Title (one or two lines) + format block in the remaining space.
    final mid = look.vhsLeft
        ? Rect.fromLTRB(vhs.right + 48, top + 26, rating.left - 40, s.height - 16)
        : Rect.fromLTRB(look.framed ? 100 : 46, top + 26, vhs.left - 40, s.height - 16);
    const spec = TitleFitSpec(
      maxFontSize: 58,
      minFontSize: 40,
      minFontSizeMultiLine: 24,
      trackingEm: 0.02,
      maxLines: 2,
      lineGapEm: 0.12,
      mainAlign: TitleAlign.start,
      crossAlign: TitleAlign.center,
    );
    const titleH = 64.0;
    final fit = TitleFitter.fit(ctx.data.title, Size(mid.width, titleH), spec);
    fit.paint(canvas, mid.topLeft, color: ink, recorder: ctx.recorder);
    final fmt = FittedLabel.fit('VHS · HI-FI STEREO',
        family: LabelFonts.text,
        weight: FontWeight.w700,
        size: 18,
        maxWidth: mid.width,
        maxHeight: 18,
        trackingEm: 0.24,
        color: ink.withValues(alpha: 0.85),
        ink: InkMetrics.figtree);
    final fmtBase = mid.top + titleH + 18 + fmt.capHeight;
    fmt.paint(canvas, mid.left, fmtBase, recorder: ctx.recorder);
    final meta = [
      if (ctx.data.year != null) ctx.data.year!,
      if (ctx.data.runtime != null) ctx.data.runtime!.toUpperCase(),
      ctx.data.isMovie ? 'FEATURE' : 'SERIES',
    ].join('  ·  ');
    final metaColor = LabelColors.contrast(ctx.lead, look.strip) > 3.2
        ? ctx.lead
        : ink.withValues(alpha: 0.7);
    final m = FittedLabel.fit(meta,
        family: LabelFonts.text,
        weight: FontWeight.w600,
        size: 16,
        maxWidth: mid.width,
        maxHeight: 16,
        trackingEm: 0.2,
        color: metaColor,
        ink: InkMetrics.figtree);
    m.paint(canvas, mid.left, fmtBase + 16 + m.capHeight, recorder: ctx.recorder);
  }

  /// Designed no-poster cover: deep ground, a geometric motif in the
  /// palette (sun with cut lines, rings, stripes or a halftone field) and
  /// big set type — title, year, genres.
  /// One of four geometric motifs in the palette, filling [r] (used by the
  /// no-poster cover and as abstract "stills" on the back).
  static void motif(Canvas canvas, Rect r, LabelContext ctx, int motif,
      {bool swap = false}) {
    final pal = ctx.palette;
    final k = r.width / 1070; // motif scale relative to a full front
    canvas.save();
    canvas.clipRect(r);
    final ground = LabelColors.mix(pal.ink, LabelColors.printBlack, 0.3);
    _p.color = ground;
    canvas.drawRect(r, _p);
    final lead = swap ? ctx.second : ctx.lead;
    final second = swap ? ctx.lead : ctx.second;
    switch (motif % 4) {
      case 0: // striped sun
        final c = Offset(r.left + r.width * 0.62, r.top + math.min(r.height * 0.34, r.width * 0.6));
        final rad = r.width * 0.5;
        _p.color = const Color(0xFF000000); // shaders are modulated by alpha
        _p.shader = ui.Gradient.linear(c - Offset(0, rad), c + Offset(0, rad),
            [second, lead]);
        canvas.drawCircle(c, rad, _p);
        _p.shader = null;
        _p.color = ground;
        for (var i = 0; i < 7; i++) {
          final y = c.dy + rad * (0.0 + i * 0.14);
          canvas.drawRect(
              Rect.fromLTRB(c.dx - rad, y, c.dx + rad, y + rad * (0.02 + i * 0.016)), _p);
        }
      case 1: // concentric rings
        final c = Offset(r.left + r.width * 0.78, r.top + math.min(r.height * 0.26, r.width * 0.46));
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 34 * k;
        for (var i = 0; i < 12; i++) {
          _p.color = i.isEven ? lead : second.withValues(alpha: 0.9);
          canvas.drawCircle(c, (60 + i * 62.0) * k, _p);
        }
        _p.style = PaintingStyle.fill;
      case 2: // bold diagonal stripes
        canvas.save();
        canvas.translate(r.left + r.width * 0.5, r.top + math.min(r.height * 0.3, r.width * 0.5));
        canvas.rotate(-0.42);
        final cols = [lead, second, LabelColors.mix(lead, second, 0.5)];
        for (var i = 0; i < 3; i++) {
          _p.color = cols[i];
          canvas.drawRect(
              Rect.fromLTWH(-1400 * k, (-260 + i * 150.0) * k, 2800 * k, 110 * k), _p);
        }
        canvas.restore();
      default: // halftone field fading down
        final pts = <List<double>>[[], [], [], [], []];
        final pitch = 34.0 * math.max(k, 0.5);
        final extent = math.max(r.height * 0.62, math.min(r.height, r.width * 0.9));
        for (var y = r.top + pitch / 2; y < r.top + extent; y += pitch) {
          final t = (y - r.top) / extent;
          final b = (t * 5).floor().clamp(0, 4);
          final row = ((y - r.top) / pitch).floor();
          for (var x = r.left + (row.isOdd ? pitch / 2 : 0); x < r.right; x += pitch) {
            pts[b]
              ..add(x)
              ..add(y);
          }
        }
        for (var b = 0; b < 5; b++) {
          _p
            ..color = LabelColors.mix(lead, second, b / 4)
            ..strokeWidth = pitch * (0.92 - b * 0.17)
            ..strokeCap = StrokeCap.round;
          canvas.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts[b]), _p);
        }
    }
    LabelPrint.vignette(canvas, r, strength: 0.2);
    canvas.restore();
  }

  static void typographicCover(Canvas canvas, Rect r, LabelContext ctx) {
    final pal = ctx.palette;
    final rng = ctx.rng('front-fallback');
    final motifIndex = rng.nextInt(4);
    final ground = LabelColors.mix(pal.ink, LabelColors.printBlack, 0.3);
    final lead = ctx.lead;
    motif(canvas, r, ctx, motifIndex);
    canvas.save();
    canvas.clipRect(r);

    // Type block, bottom-left.
    const m = 70.0;
    final paper = pal.paper;
    final genres = ctx.data.genres.take(3).map((g) => g.toUpperCase()).join('  ·  ');
    var y = r.bottom - m;
    if (genres.isNotEmpty) {
      final g = FittedLabel.fit(genres,
          family: LabelFonts.text,
          weight: FontWeight.w700,
          size: 26,
          maxWidth: r.width - 2 * m,
          maxHeight: 26,
          trackingEm: 0.22,
          color: paper.withValues(alpha: 0.85),
          ink: InkMetrics.figtree);
      g.paint(canvas, r.left + m, y, recorder: ctx.recorder);
      y -= g.capHeight + 44;
    }
    // Accent rule.
    _p.color = lead;
    canvas.drawRect(Rect.fromLTWH(r.left + m, y - 10, 150, 12), _p);
    y -= 44;
    const spec = TitleFitSpec(
      maxFontSize: 230,
      minFontSize: 120,
      minFontSizeMultiLine: 80,
      trackingEm: 0.005,
      minTrackingEm: -0.02,
      maxLines: 4,
      lineGapEm: 0.1,
      mainAlign: TitleAlign.start,
      crossAlign: TitleAlign.end,
    );
    const titleH = 640.0;
    double nameTop;
    if (ctx.logo != null) {
      // The show's own logo is the title: big, bottom-left, over the motif.
      final box = Rect.fromLTRB(r.left + m, y - titleH * 0.6, r.right - m, y);
      final placed = LabelArt.logo(canvas, ctx.logo!, ctx.logoInfo, box,
          ground: ground, align: -1, recorder: ctx.recorder);
      nameTop = placed.top;
    } else {
      final fit = TitleFitter.fit(ctx.data.title, Size(r.width - 2 * m, titleH), spec);
      fit.paint(canvas, Offset(r.left + m, y - titleH), color: paper, recorder: ctx.recorder);
      nameTop = y - titleH + fit.inkBounds.top;
    }
    final yearText = ctx.data.year;
    if (yearText != null) {
      final yr = FittedLabel.fit(yearText,
          family: LabelFonts.text,
          weight: FontWeight.w800,
          size: 46,
          maxWidth: 400,
          maxHeight: 46,
          trackingEm: 0.12,
          color: LabelColors.contrast(lead, ground) > 3 ? lead : paper,
          ink: InkMetrics.figtree);
      yr.paint(canvas, r.left + m, nameTop - 40, recorder: ctx.recorder);
    }
    canvas.restore();
  }
}

/// Colour/arrangement variant of the front's house style.
class _FrontLook {
  const _FrontLook({
    required this.band,
    required this.bandText,
    required this.strip,
    required this.stripText,
    required this.vhsLeft,
    required this.framed,
  });

  final Color band, bandText, strip, stripText;
  final bool vhsLeft, framed;
}