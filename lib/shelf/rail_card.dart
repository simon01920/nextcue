import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../theme/tokens.dart';
import 'plates/plate_manifest.dart';

/// Paints the rail's section card (the `tag` atlas: one `card` region,
/// 352 × 19 mm) — a cream paper strip with the section name, like the
/// reference in tools/plates/composite.py.
class RailCard {
  RailCard._();

  static const Color paper = Color(0xFFECE6D6);
  static const Color ink = Color(0xFF1E1C1A);
  static const Color rule = Color(0xFFC83C28);

  /// The card for [text] at [pxPerMm] (3 px/mm is 1 : 1 with the shelf).
  static Future<ui.Image> render(String text, PlateAtlas atlas,
      {double pxPerMm = 3}) {
    final size = atlas.pixelSize(pxPerMm);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Offset.zero & size);
    final card = atlas.regions['card'] ?? const Rect.fromLTWH(0, 0, 1, 1);
    paint(
      canvas,
      Rect.fromLTWH(card.left * size.width, card.top * size.height,
          card.width * size.width, card.height * size.height),
      text,
    );
    final picture = rec.endRecording();
    return picture
        .toImage(size.width.round(), size.height.round())
        .whenComplete(picture.dispose);
  }

  static void paint(Canvas canvas, Rect r, String text) {
    canvas.drawRect(r, Paint()..color = paper);
    final h = r.height;
    canvas.drawRect(
        Rect.fromLTRB(r.left, r.bottom - h * 0.055, r.right, r.bottom),
        Paint()..color = rule);
    final style = ui.ParagraphStyle(maxLines: 1, ellipsis: '…');
    final b = ui.ParagraphBuilder(style)
      ..pushStyle(ui.TextStyle(
        color: ink,
        fontFamily: AppTextStyles.uiFamily,
        fontWeight: FontWeight.w800,
        fontSize: h * 0.46,
        letterSpacing: h * 0.02,
      ))
      ..addText(text.toUpperCase());
    final p = b.build()
      ..layout(ui.ParagraphConstraints(width: r.width - h));
    canvas.drawParagraph(
        p, Offset(r.left + h * 0.5, r.top + (h - p.height) / 2 - h * 0.02));
  }
}
