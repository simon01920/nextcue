import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'cover_painter.dart';
import 'label_art.dart';
import 'label_palette.dart';
import 'label_print.dart';
import 'label_rng.dart';
import 'label_text.dart';
import 'label_wear.dart';
import 'spine_style.dart';
import 'title_fitter.dart';

/// Paints the sleeve back (107 × 190.5 mm); its right edge is the spine
/// fold. Title, meta line, three stills, auto-fitted synopsis, billing
/// block, format badges, rewind reminder, barcode and legal line.
class BackCoverPainter {
  BackCoverPainter._();

  static final Paint _p = Paint();
  static const double _m = 66; // page margin

  static bool isLight(LabelContext ctx) =>
      ctx.style.kind == SpineStyleKind.paperRules ||
      (ctx.style.kind == SpineStyleKind.rainbow && ctx.style.variant < 2);

  static void paint(Canvas canvas, Rect rect, LabelContext ctx) {
    ctx.region('back');
    canvas.save();
    // Hard region edges: complementary anti-aliased clips would leave a
    // half-transparent seam where two regions meet on a fractional pixel.
    canvas.clipRect(rect, doAntiAlias: false);
    canvas.translate(rect.left, rect.top);
    final s = rect.size;
    final light = isLight(ctx);
    final pal = ctx.palette;
    final ground = light
        ? LabelColors.mix(pal.paper, LabelColors.paper, 0.4)
        : LabelColors.mix(pal.ink, LabelColors.printBlack, 0.45);
    final text = light
        ? LabelColors.mix(pal.ink, LabelColors.printBlack, 0.6)
        : pal.paper;
    final lead = ctx.lead;
    _p.color = ground;
    canvas.drawRect(Offset.zero & s, _p);
    // Lead colour bar at the head.
    _p.color = lead;
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, 22), _p);

    final w = s.width - 2 * _m;
    // Title.
    const spec = TitleFitSpec(
      maxFontSize: 120,
      minFontSize: 70,
      minFontSizeMultiLine: 56,
      trackingEm: 0.01,
      maxLines: 2,
      lineGapEm: 0.1,
      mainAlign: TitleAlign.start,
      crossAlign: TitleAlign.start,
    );
    final fit = TitleFitter.fit(ctx.data.title, Size(w, 230), spec);
    fit.paint(canvas, const Offset(_m, 78), color: text, recorder: ctx.recorder);
    var y = 78 + fit.inkBounds.bottom + 34;
    // Meta line.
    final metaParts = <String>[
      if (ctx.data.year != null) ctx.data.year!,
      ...ctx.data.genres.take(3),
      if (ctx.data.network != null) ctx.data.network!,
      if (ctx.data.runtime != null) ctx.data.runtime!,
    ];
    if (metaParts.isNotEmpty) {
      final metaColor = LabelColors.contrast(lead, ground) >= 3
          ? lead
          : text.withValues(alpha: 0.8);
      final meta = FittedLabel.fit(metaParts.join('  ·  ').toUpperCase(),
          family: LabelFonts.text,
          weight: FontWeight.w700,
          size: 25,
          maxWidth: w,
          maxHeight: 25,
          trackingEm: 0.14,
          color: metaColor,
          ink: InkMetrics.figtree);
      meta.paint(canvas, _m, y + meta.capHeight, recorder: ctx.recorder);
      y += meta.capHeight + 40;
    }

    // The main image (TVDB background / fanart), then synopsis beside two
    // stills cropped from the same art.
    const gap = 26.0;
    final bigTop = math.max(y, 330.0);
    final bigH = bigTop <= 340 ? 456.0 : 412.0;
    _still(canvas, Rect.fromLTWH(_m, bigTop, w, bigH), ctx, 0, light);
    final colTop = bigTop + bigH + 46;
    const colBottom = 1300.0;
    final synopsis = (ctx.data.synopsis ?? '').trim();
    if (synopsis.isEmpty) {
      // No synopsis: the two stills share the row instead.
      final sw2 = (w - gap) / 2;
      final sh2 = math.min(colBottom - colTop, sw2 * 0.75);
      _still(canvas, Rect.fromLTWH(_m, colTop, sw2, sh2), ctx, 1, light);
      _still(canvas, Rect.fromLTWH(_m + sw2 + gap, colTop, sw2, sh2), ctx, 2, light);
    } else {
      const smallW = 330.0;
      final smallH = math.min(250.0, (colBottom - colTop - gap) / 2);
      final smallX = s.width - _m - smallW;
      _still(canvas, Rect.fromLTWH(smallX, colTop, smallW, smallH), ctx, 1, light);
      _still(canvas, Rect.fromLTWH(smallX, colTop + smallH + gap, smallW, smallH), ctx, 2,
          light);
      // Synopsis, auto-fitted then ellipsised, in the left column.
      final synBox = Rect.fromLTRB(_m, colTop - 6, smallX - 40, colBottom);
      _synopsis(canvas, synopsis, synBox, text, lead, ctx);
    }

    // Billing block: tall condensed credits.
    _billing(canvas, Rect.fromLTRB(_m, 1340, s.width - _m, 1460), text, ctx);

    // Bottom row: rewind reminder | badges | barcode.
    const rowTop = 1512.0;
    _rewindBadge(canvas, const Rect.fromLTWH(_m, rowTop, 300, 150), text, lead, ctx);
    _badges(canvas, const Rect.fromLTWH(_m + 330, rowTop, 300, 150), text, ctx);
    _barcode(canvas, Rect.fromLTWH(s.width - _m - 280, rowTop - 4, 280, 172), ctx);

    // Legal line.
    final year = ctx.data.year ?? '';
    final legal = '© $year NextCue Home Video. All rights reserved. '
        'Unauthorised copying, hiring, lending, public performance and '
        'broadcasting of this videocassette are prohibited. '
        '${ctx.catalogueNo} · PAL · Colour';
    final p = LabelText.paragraph(legal,
        family: LabelFonts.text,
        size: 15.5,
        weight: FontWeight.w500,
        letterSpacing: 0.3,
        color: text.withValues(alpha: 0.7),
        width: w,
        maxLines: 3,
        ellipsis: true,
        height: 1.3);
    final legalTop = s.height - 64 - p.height;
    canvas.drawParagraph(p, Offset(_m, legalTop));
    ctx.recorder?.record(canvas, 'legal', Rect.fromLTWH(_m, legalTop, p.width, p.height));
    // Hairline above legal.
    _p.color = text.withValues(alpha: 0.35);
    canvas.drawRect(Rect.fromLTWH(_m, legalTop - 20, w, 2), _p);

    LabelPrint.grain(canvas, Offset.zero & s, ctx.grain, opacity: 0.14);
    LabelWear.paint(canvas, Offset.zero & s,
        titleId: ctx.data.titleId,
        salt: 'back',
        level: ctx.wear,
        edges: const WearEdges(left: 0.8, top: 1, right: 1.5, bottom: 1));
    canvas.restore();
  }

  /// Still [i] (0 = the main image): from the background art, else crops of
  /// the poster, else an abstract motif in the palette.
  static void _still(Canvas canvas, Rect r, LabelContext ctx, int i, bool light) {
    final poster = ctx.data.poster;
    final background = ctx.data.background;
    // Keyline frame.
    _p.color = light ? LabelColors.printBlack : LabelColors.paper;
    canvas.drawRect(r.inflate(5), _p);
    if (background != null) {
      // Main: the whole frame; stills: two tighter "frames" from it.
      const crops = [(0.0, 0.0, 1.0), (-0.7, 0.2, 2.1), (0.75, -0.1, 2.4)];
      final (ax, ay, zoom) = crops[i];
      LabelArt.photo(canvas, background, r,
          alignX: ax, alignY: ay, zoom: zoom, vignette: i == 0 ? 0.16 : 0.22);
    } else if (poster != null) {
      // Crops from the middle band of the art, where posters rarely carry
      // type: a wide establishing frame and two close-ups.
      const crops = [(0.0, -0.05, 1.25), (-0.75, 0.15, 2.5), (0.7, -0.15, 2.2)];
      final (ax, ay, zoom) = crops[i];
      LabelPrint.cover(canvas, poster, r, alignX: ax, alignY: ay, zoom: zoom);
      LabelPrint.vignette(canvas, r, strength: 0.22);
    } else {
      final base = ctx.rng('front-fallback').nextInt(4);
      FrontCoverPainter.motif(canvas, r, ctx, base + 1 + i, swap: i.isOdd);
    }
  }

  /// The synopsis with its first sentence set as a bold lead-in.
  static ui.Paragraph _synParagraph(String synopsis, double size, Color color,
      double width, {int? maxLines}) {
    final m = RegExp(r'^.{12,160}?[.!?](?=\s|$)', dotAll: true).firstMatch(synopsis);
    final lead = m?.group(0) ?? '';
    final rest = synopsis.substring(lead.length);
    // Ragged right: a 56 mm column justified opens rivers.
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    ));
    if (lead.isNotEmpty) {
      b.pushStyle(ui.TextStyle(
          fontFamily: LabelFonts.text,
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.36));
      b.addText(lead);
      b.pop();
    }
    b.pushStyle(ui.TextStyle(
        fontFamily: LabelFonts.text,
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color.withValues(alpha: 0.92),
        height: 1.36));
    b.addText(rest);
    LabelText.builds++;
    return b.build()..layout(ui.ParagraphConstraints(width: width));
  }

  static void _synopsis(Canvas canvas, String synopsis, Rect box, Color color,
      Color lead, LabelContext ctx) {
    ui.Paragraph? chosen;
    // Largest size that fits, coarse steps first.
    for (var size = 36.0; size >= 23; size -= 1.5) {
      final p = _synParagraph(synopsis, size, color, box.width);
      if (p.height <= box.height) {
        chosen = p;
        break;
      }
    }
    if (chosen == null) {
      // Minimum size, as many lines as fit, ellipsis.
      const size = 23.0;
      final probe = _synParagraph('Ag', size, color, box.width);
      final lines = math.max(1, (box.height / probe.height).floor());
      chosen = _synParagraph(synopsis, size, color, box.width, maxLines: lines);
    }
    canvas.drawParagraph(chosen, box.topLeft);
    ctx.recorder?.record(
        canvas, 'synopsis', Rect.fromLTWH(box.left, box.top, chosen.width, chosen.height));
  }

  static void _billing(Canvas canvas, Rect box, Color color, LabelContext ctx) {
    final d = ctx.data;
    final title = TitleFitter.caseMap(d.title);
    final parts = <String>[
      'NEXTCUE HOME VIDEO PRESENTS',
      if (d.network != null) 'A ${d.network!.toUpperCase()} ${d.isMovie ? 'PICTURE' : 'PRODUCTION'}',
      title,
      if (d.genres.isNotEmpty) d.genres.take(2).join(' / ').toUpperCase(),
      if (d.runtime != null) 'RUNNING TIME ${d.runtime!.toUpperCase()}',
      if (d.year != null) '©\u00A0${roman(d.year!)}',
    ];
    final text = parts.join('   ');
    // Anton stretched 1.7× vertically: the classic billing-block look.
    const stretch = 1.7;
    final p = LabelText.paragraph(text,
        family: LabelFonts.display,
        size: 22,
        letterSpacing: 0.6,
        color: color.withValues(alpha: 0.82),
        width: box.width,
        align: TextAlign.center,
        maxLines: 3,
        ellipsis: true,
        height: 1.12);
    final h = p.height * stretch;
    final top = box.top + math.max(0, (box.height - h) / 2);
    canvas.save();
    canvas.translate(box.left, top);
    canvas.scale(1, stretch);
    canvas.drawParagraph(p, Offset.zero);
    ctx.recorder?.record(canvas, 'billing', Rect.fromLTWH(0, 0, p.width, p.height));
    canvas.restore();
  }

  /// Roman numerals for the copyright year ("1994" → "MCMXCIV"), as in
  /// film credits; falls back to the digits.
  static String roman(String year) {
    var n = int.tryParse(year.trim());
    if (n == null || n < 1 || n > 3999) return year;
    const vals = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const syms = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
    final b = StringBuffer();
    for (var i = 0; i < vals.length; i++) {
      while (n! >= vals[i]) {
        b.write(syms[i]);
        n -= vals[i];
      }
    }
    return b.toString();
  }

  static void _rewindBadge(
      Canvas canvas, Rect r, Color text, Color lead, LabelContext ctx) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(18));
    _p
      ..color = text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(rr, _p);
    _p.style = PaintingStyle.fill;
    // ◀◀ icon.
    _p.color = lead;
    final c = Offset(r.left + 58, r.center.dy);
    canvas.drawPath(LabelPrint.triangle(c.translate(-15, 0), 52, left: true), _p);
    canvas.drawPath(LabelPrint.triangle(c.translate(15, 0), 52, left: true), _p);
    final tx = r.left + 112;
    final avail = r.right - 18 - tx;
    final l1 = FittedLabel.fit('BE KIND,',
        family: LabelFonts.display,
        size: 40,
        maxWidth: avail,
        maxHeight: 36,
        trackingEm: 0.04,
        color: text,
        ink: InkMetrics.anton);
    final l2 = FittedLabel.fit('PLEASE REWIND',
        family: LabelFonts.display,
        size: 40,
        maxWidth: avail,
        maxHeight: 36,
        trackingEm: 0.04,
        color: text,
        ink: InkMetrics.anton);
    final total = l1.capHeight + 14 + l2.capHeight;
    final top = r.center.dy - total / 2;
    l1.paint(canvas, tx, top + l1.capHeight, recorder: ctx.recorder);
    l2.paint(canvas, tx, top + total, recorder: ctx.recorder);
  }

  static void _badges(Canvas canvas, Rect r, Color text, LabelContext ctx) {
    // VHS logo + three small format pills in a 2×2 grid.
    final cellW = (r.width - 16) / 2;
    final cellH = (r.height - 16) / 2;
    LabelPrint.vhsLogo(canvas, Rect.fromLTWH(r.left, r.top, cellW, cellH), text,
        recorder: ctx.recorder);
    final pills = ['HI-FI', 'PAL', ctx.data.isMovie ? 'COLOUR' : 'STEREO'];
    final cells = [
      Rect.fromLTWH(r.left + cellW + 16, r.top, cellW, cellH),
      Rect.fromLTWH(r.left, r.top + cellH + 16, cellW, cellH),
      Rect.fromLTWH(r.left + cellW + 16, r.top + cellH + 16, cellW, cellH),
    ];
    for (var i = 0; i < 3; i++) {
      final c = cells[i];
      final rr = RRect.fromRectAndRadius(c, Radius.circular(c.height / 2));
      _p.color = text;
      canvas.drawRRect(rr, _p);
      final f = FittedLabel.fit(pills[i],
          family: LabelFonts.text,
          weight: FontWeight.w800,
          size: 24,
          maxWidth: c.width - 36,
          maxHeight: 24,
          trackingEm: 0.12,
          color: BackCoverPainter.isLight(ctx)
              ? LabelColors.paper
              : LabelColors.mix(ctx.palette.ink, LabelColors.printBlack, 0.4),
          ink: InkMetrics.figtree);
      f.paintIn(canvas, c, recorder: ctx.recorder);
    }
  }

  // EAN-13 tables.
  static const List<String> _l = [
    '0001101', '0011001', '0010011', '0111101', '0100011',
    '0110001', '0101111', '0111011', '0110111', '0001011',
  ];
  static const List<String> _g = [
    '0100111', '0110011', '0011011', '0100001', '0011101',
    '0111001', '0000101', '0010001', '0001001', '0010111',
  ];
  static const List<String> _r = [
    '1110010', '1100110', '1101100', '1000010', '1011100',
    '1001110', '1010000', '1000100', '1001000', '1110100',
  ];
  static const List<String> _parity = [
    'LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG',
    'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL',
  ];

  /// Deterministic EAN-13 digits for a title (GS1 prefix 858, Slovakia).
  static String eanDigits(String titleId) {
    final rng = LabelRng.forTitle(titleId, 'barcode');
    final b = StringBuffer('858');
    for (var i = 0; i < 9; i++) {
      b.write(rng.nextInt(10));
    }
    final d = b.toString();
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(d[i]) * (i.isOdd ? 3 : 1);
    }
    return '$d${(10 - sum % 10) % 10}';
  }

  /// The 95-module bar pattern for [digits].
  static String eanModules(String digits) {
    final first = int.parse(digits[0]);
    final b = StringBuffer('101');
    for (var i = 1; i <= 6; i++) {
      final d = int.parse(digits[i]);
      b.write(_parity[first][i - 1] == 'L' ? _l[d] : _g[d]);
    }
    b.write('01010');
    for (var i = 7; i <= 12; i++) {
      b.write(_r[int.parse(digits[i])]);
    }
    b.write('101');
    return b.toString();
  }

  static void _barcode(Canvas canvas, Rect r, LabelContext ctx) {
    _p.color = const Color(0xFFFAF8F2);
    canvas.drawRect(r, _p);
    final digits = eanDigits(ctx.data.titleId);
    final modules = eanModules(digits);
    const quiet = 22.0;
    final mw = (r.width - 2 * quiet) / 95;
    final barTop = r.top + 16;
    final barBottom = r.bottom - 44;
    _p.color = LabelColors.printBlack;
    var i = 0;
    while (i < modules.length) {
      if (modules[i] == '1') {
        var j = i;
        while (j < modules.length && modules[j] == '1') {
          j++;
        }
        final guard = i < 3 || (i >= 45 && i < 50) || i >= 92;
        canvas.drawRect(
            Rect.fromLTRB(r.left + quiet + i * mw, barTop, r.left + quiet + j * mw,
                guard ? barBottom + 14 : barBottom),
            _p);
        i = j;
      } else {
        i++;
      }
    }
    final txt = '${digits[0]}  ${digits.substring(1, 7)}  ${digits.substring(7)}';
    final f = FittedLabel.fit(txt,
        family: LabelFonts.text,
        weight: FontWeight.w600,
        size: 24,
        maxWidth: r.width - 24,
        maxHeight: 24,
        trackingEm: 0.08,
        color: LabelColors.printBlack,
        ink: InkMetrics.figtree);
    f.paint(canvas, r.center.dx - f.width / 2, r.bottom - 10, recorder: ctx.recorder);
  }
}
