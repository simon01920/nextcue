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

/// Paper stickers on the cassette shell: the face label (79 × 43 mm) and
/// the spine label (147 × 19 mm). Matte paper, upright landscape.
///
/// * Face: the logo (or title) over a crop of the TVDB background (else the
///   banner), with the state sticker; without either image, a ruled paper
///   label with the logo/title and a rubber state stamp.
/// * Spine: the TVDB banner printed as the sticker; without it, the logo
///   (or title) on a palette colour. Both keep the tape-counter window.
class CassettePainter {
  CassettePainter._();

  static final Paint _p = Paint();
  static const Color _rule = Color(0xFF9FB3C8);

  static Color _labelPaper(LabelContext ctx) =>
      LabelColors.mix(LabelColors.paper, const Color(0xFFFFFFFF), 0.35);

  static Color _ink(LabelContext ctx) =>
      LabelColors.mix(ctx.palette.ink, LabelColors.printBlack, 0.7);

  /// Stamp wording and ink for a state.
  static (String, String?, Color) stampFor(TapeState st, bool isMovie) =>
      switch (st.kind) {
        TapeStateKind.notStarted => ('Sealed', null, const Color(0xFF1F4FA8)),
        TapeStateKind.watching => (
            'Watching',
            st.nextCode,
            const Color(0xFFC8102E)
          ),
        TapeStateKind.completed => ('Watched', null, const Color(0xFF1E7A3C)),
        TapeStateKind.newEpisode => ('New Ep', st.nextCode, const Color(0xFFC8102E)),
      };

  static const double _headerH = 80;

  static void _header(Canvas canvas, Size s, LabelContext ctx) {
    final lead = ctx.lead;
    final onLead = ctx.palette.on(lead);
    _p.color = lead;
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, _headerH), _p);
    LabelPrint.studioMark(canvas, const Offset(32 + 21, _headerH / 2), 42,
        disc: onLead, glyph: lead);
    final studio = FittedLabel.fit('NEXTCUE HOME VIDEO',
        family: LabelFonts.text,
        weight: FontWeight.w800,
        size: 19,
        maxWidth: s.width - 330,
        maxHeight: 19,
        trackingEm: 0.24,
        color: onLead,
        ink: InkMetrics.figtree);
    studio.paint(canvas, 92, _headerH / 2 + studio.capHeight / 2, recorder: ctx.recorder);
    LabelPrint.vhsLogo(
        canvas, Rect.fromLTWH(s.width - 32 - 98, _headerH / 2 - 21, 98, 42), onLead,
        recorder: ctx.recorder);
  }

  static void _finish(Canvas canvas, Size s, LabelContext ctx, String salt) {
    LabelPrint.grain(canvas, Offset.zero & s, ctx.grain, opacity: 0.12, texel: 1.5);
    LabelWear.paint(canvas, Offset.zero & s,
        titleId: ctx.data.titleId,
        salt: salt,
        level: ctx.wear * 0.5,
        board: const Color(0xFFFFFFFF),
        edges: const WearEdges(left: 0.6, top: 0.6, right: 0.6, bottom: 0.6));
  }

  // ── face ───────────────────────────────────────────────────────────────

  static void paintFace(Canvas canvas, Rect rect, LabelContext ctx) {
    ctx.region('cassette_face');
    canvas.save();
    // Hard region edges: complementary anti-aliased clips would leave a
    // half-transparent seam where two regions meet on a fractional pixel.
    canvas.clipRect(rect, doAntiAlias: false);
    canvas.translate(rect.left, rect.top);
    final s = rect.size;
    _p.color = _labelPaper(ctx);
    canvas.drawRect(Offset.zero & s, _p);
    _header(canvas, s, ctx);
    final photo = ctx.data.background ?? ctx.data.banner;
    if (photo != null) {
      _photoFace(canvas, s, ctx, photo);
    } else {
      _paperFace(canvas, s, ctx);
    }
    _finish(canvas, s, ctx, 'cassette-face');
    canvas.restore();
  }

  /// Logo or title over a crop of the background (or banner), meta typed
  /// on a ruled line below, the state sticker slapped on the corner.
  static void _photoFace(Canvas canvas, Size s, LabelContext ctx, ui.Image photo) {
    const m = 22.0;
    final window = Rect.fromLTRB(m, _headerH + 14, s.width - m, s.height - 92);
    canvas.save();
    canvas.clipRect(window);
    if (identical(photo, ctx.data.background)) {
      LabelArt.photo(canvas, photo, window, alignY: -0.15, vignette: 0.2);
    } else {
      // A banner usually carries its own lettering, and a crop would cut it
      // mid-word: print the crop defocused, as a colour backdrop for the
      // logo/title set over it.
      canvas.saveLayer(window, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22));
      // The right end of a banner is usually picture, not lettering.
      LabelArt.photo(canvas, photo, window.inflate(60), alignX: 1, vignette: 0);
      canvas.restore();
      LabelPrint.vignette(canvas, window, strength: 0.25);
    }
    final ink = LabelColors.mix(ctx.palette.ink, LabelColors.printBlack, 0.4);
    LabelArt.scrim(canvas, window, ink, from: 0.3, strength: 0.9);
    final nameBox = Rect.fromLTRB(window.left + 22, window.top + window.height * 0.4,
        window.left + window.width * 0.64, window.bottom - 16);
    if (ctx.logo != null) {
      LabelArt.logo(canvas, ctx.logo!, ctx.logoInfo, nameBox,
          ground: ink, align: -1, recorder: ctx.recorder);
    } else {
      const spec = TitleFitSpec(
        maxFontSize: 80,
        minFontSize: 44,
        minFontSizeMultiLine: 34,
        trackingEm: 0.015,
        maxLines: 2,
        lineGapEm: 0.1,
        mainAlign: TitleAlign.start,
        crossAlign: TitleAlign.end,
      );
      final fit = TitleFitter.fit(ctx.data.title, nameBox.size, spec);
      fit.paint(canvas, nameBox.topLeft, color: ctx.palette.paper, recorder: ctx.recorder);
    }
    canvas.restore();
    // Thin keyline round the photo window (printed border).
    _p
      ..color = _ink(ctx)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(window, _p);
    _p.style = PaintingStyle.fill;

    // Typed details on a ruled line.
    final inkC = _ink(ctx);
    final lineY = s.height - 30;
    _p.color = _rule;
    canvas.drawRect(Rect.fromLTWH(m + 6, lineY, s.width - 2 * m - 220, 2.4), _p);
    final st = ctx.data.state;
    final typed = [
      if (ctx.data.year != null) ctx.data.year!,
      if (ctx.data.runtime != null) ctx.data.runtime!,
      ctx.data.isMovie
          ? 'Feature'
          : (st.total > 0 ? 'Ep ${st.watched}/${st.total}' : 'Series'),
      'SP',
    ].join('  ·  ');
    final f = FittedLabel.fit(typed,
        family: LabelFonts.text,
        weight: FontWeight.w500,
        size: 25,
        maxWidth: s.width - 2 * m - 240,
        maxHeight: 25,
        trackingEm: 0.04,
        color: inkC.withValues(alpha: 0.86));
    f.paint(canvas, m + 10, lineY - 10, recorder: ctx.recorder);

    // State sticker on the corner, like the one on the spine.
    final rng = ctx.rng('face-sticker');
    LabelStickers.paintForState(
      canvas,
      Offset(s.width - 112 + rng.jitter(8), s.height - 92 + rng.jitter(6)),
      st,
      isMovie: ctx.data.isMovie,
      tilt: rng.range(-0.14, 0.1),
      grain: ctx.grain,
      rng: ctx.rng('sticker'),
      grounds: [ctx.palette.ink, _labelPaper(ctx)],
      scale: 0.62,
      recorder: ctx.recorder,
    );
  }

  /// No artwork: a ruled paper label — logo or title, typed details and a
  /// rubber state stamp.
  static void _paperFace(Canvas canvas, Size s, LabelContext ctx) {
    final ink = _ink(ctx);
    const m = 40.0;
    final titleBox = Rect.fromLTRB(m, _headerH + 22, s.width - m, _headerH + 160);
    if (ctx.logo != null) {
      LabelArt.logo(canvas, ctx.logo!, ctx.logoInfo, titleBox,
          ground: _labelPaper(ctx), align: -1, recorder: ctx.recorder);
    } else {
      const spec = TitleFitSpec(
        maxFontSize: 96,
        minFontSize: 52,
        minFontSizeMultiLine: 40,
        trackingEm: 0.015,
        maxLines: 2,
        lineGapEm: 0.1,
        mainAlign: TitleAlign.start,
        crossAlign: TitleAlign.center,
      );
      final fit = TitleFitter.fit(ctx.data.title, titleBox.size, spec);
      fit.paint(canvas, titleBox.topLeft, color: ink, recorder: ctx.recorder);
    }

    // Ruled write-in lines with typed details.
    final lines = [titleBox.bottom + 56, titleBox.bottom + 112, titleBox.bottom + 168];
    _p.color = _rule;
    for (final y in lines) {
      if (y > s.height - 16) continue;
      canvas.drawRect(Rect.fromLTWH(m, y, s.width - 2 * m, 2.4), _p);
    }
    final st = ctx.data.state;
    final typed = <String>[
      [
        if (ctx.data.year != null) ctx.data.year!,
        if (ctx.data.runtime != null) ctx.data.runtime!,
        if (ctx.data.network != null) ctx.data.network!,
      ].join('  ·  '),
      ctx.data.isMovie
          ? 'Feature  ·  SP'
          : (st.total > 0 ? 'Episodes ${st.watched}/${st.total}  ·  SP' : 'Series  ·  SP'),
    ];
    for (var i = 0; i < typed.length; i++) {
      if (typed[i].isEmpty || lines[i] > s.height - 16) continue;
      final f = FittedLabel.fit(typed[i],
          family: LabelFonts.text,
          weight: FontWeight.w500,
          size: 26,
          maxWidth: s.width - 2 * m - 250,
          maxHeight: 26,
          trackingEm: 0.04,
          color: ink.withValues(alpha: 0.86));
      f.paint(canvas, m + 6, lines[i] - 9, recorder: ctx.recorder);
    }

    // State stamp, bottom right.
    final (word, sub, stampInk) = stampFor(st, ctx.data.isMovie);
    final rng = ctx.rng('stamp');
    LabelStickers.stamp(
      canvas,
      Offset(s.width - 150 + rng.jitter(10), s.height - 76 + rng.jitter(6)),
      sub == null ? word : '$word ${sub.toUpperCase()}',
      color: stampInk,
      tilt: -0.16 + rng.jitter(0.06),
      speckle: ctx.speckle,
      height: 62,
      maxWidth: 250,
      recorder: ctx.recorder,
    );
  }

  // ── spine ──────────────────────────────────────────────────────────────

  static void paintSpine(Canvas canvas, Rect rect, LabelContext ctx) {
    ctx.region('cassette_spine');
    canvas.save();
    canvas.clipRect(rect, doAntiAlias: false);
    canvas.translate(rect.left, rect.top);
    final s = rect.size;
    final banner = ctx.data.banner;
    final lead = ctx.lead;
    // Banner stickers print on white paper; the fallback on a palette colour.
    final ground = banner != null ? _labelPaper(ctx) : lead;
    _p.color = ground;
    canvas.drawRect(Offset.zero & s, _p);

    const counterW = 300.0, margin = 14.0;
    final counter = Rect.fromLTWH(s.width - 24 - counterW, 30, counterW, s.height - 60);
    _counter(canvas, counter, ctx);
    final d = s.height * 0.5;
    final onGround = ctx.palette.on(ground);
    // Room left of the counter for the name and the studio mark.
    final contentRight = counter.left - 26 - d - 26;

    if (banner != null) {
      // The banner itself, contained at full sticker height, with a hair
      // keyline; the studio mark sits centred in the paper that's left.
      final box = Rect.fromLTRB(margin, margin, contentRight, s.height - margin);
      final bw = banner.width.toDouble(), bh = banner.height.toDouble();
      final sc = math.min(box.width / bw, box.height / bh);
      final dst = Rect.fromLTWH(box.left, box.center.dy - bh * sc / 2, bw * sc, bh * sc);
      LabelArt.photo(canvas, banner, dst, vignette: 0);
      _p
        ..color = _ink(ctx)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(dst, _p);
      _p.style = PaintingStyle.fill;
      LabelPrint.studioMark(
          canvas, Offset((dst.right + counter.left) / 2, s.height / 2), d);
    } else {
      LabelPrint.studioMark(canvas, Offset(counter.left - 26 - d / 2, s.height / 2), d,
          disc: onGround, glyph: ground);
      final zone = Rect.fromLTRB(36, 28, contentRight, s.height - 28);
      if (ctx.logo != null) {
        LabelArt.logo(canvas, ctx.logo!, ctx.logoInfo, zone,
            ground: lead, align: -1, recorder: ctx.recorder);
      } else {
        const spec = TitleFitSpec(
          maxFontSize: 120,
          minFontSize: 64,
          minFontSizeMultiLine: 44,
          trackingEm: 0.03,
          maxLines: 2,
          lineGapEm: 0.1,
          mainAlign: TitleAlign.start,
        );
        final fit = TitleFitter.fit(ctx.data.title, zone.size, spec);
        fit.paint(canvas, zone.topLeft, color: onGround, recorder: ctx.recorder);
      }
    }
    _finish(canvas, s, ctx, 'cassette-spine');
    canvas.restore();
  }

  static void _counter(Canvas canvas, Rect counter, LabelContext ctx) {
    final st = ctx.data.state;
    _p.color = const Color(0xFF151A12);
    canvas.drawRRect(RRect.fromRectAndRadius(counter, const Radius.circular(10)), _p);
    const lit = Color(0xFFB9F24C);
    final String digits;
    if (ctx.data.isMovie || st.total <= 0) {
      digits = '${(st.progress.clamp(0.0, 1.0) * 100).round().toString().padLeft(2, '0')}%';
    } else {
      String two(int v) => v.toString().padLeft(2, '0');
      digits = '${two(st.watched)}/${two(st.total)}';
    }
    final inner = counter.deflate(18);
    final triH = inner.height * 0.6;
    _p.color = lit;
    canvas.drawPath(
        LabelPrint.triangle(Offset(inner.left + triH * 0.43, inner.center.dy), triH), _p);
    SevenSegment.paint(
        canvas,
        digits,
        Rect.fromLTRB(inner.left + triH + 12, inner.top, inner.right, inner.bottom),
        on: lit,
        ghost: lit.withValues(alpha: 0.08));
  }
}
