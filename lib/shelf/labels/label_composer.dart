import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'atlas_layout.dart';
import 'back_painter.dart';
import 'cassette_painter.dart';
import 'cover_painter.dart';
import 'label_art.dart';
import 'label_palette.dart';
import 'label_print.dart';
import 'label_text.dart';
import 'spine_painter.dart';
import 'spine_style.dart';
import 'tape_label_data.dart';

/// Paints the per-title label atlases the VHS plate shader maps onto the
/// pre-rendered sleeve and cassette (see docs/LABELS.md).
///
/// Everything is painted in design units (0.1 mm of board) and scaled to
/// the requested pixel size at the end, so the shelf atlas and the hero
/// atlas are the same print at two resolutions — the spine comes from the
/// one [SpinePainter], and the shelf's `front_strip` is the left 20 mm of
/// the hero front, pixel-for-pixel in design.
///
/// Uses only `dart:ui` (PictureRecorder → Picture.toImage), so it runs on
/// CanvasKit (web) and Impeller/Skia (Android, iOS) alike.
class LabelComposer {
  LabelComposer({AtlasManifest? manifest, this.recordText = false})
      : manifest = manifest ?? AtlasManifest.standard;

  final AtlasManifest manifest;

  /// When true, every painted text box is recorded (in atlas pixels) into
  /// [lastTextPlacements] — used by tests to assert nothing overflows.
  bool recordText;

  /// Text boxes painted by the last compose call (when [recordText]).
  @visibleForTesting
  List<TextPlacement> lastTextPlacements = const <TextPlacement>[];

  /// The spine design chosen for [titleId] (deterministic).
  static SpineStyleSpec styleFor(String titleId) =>
      SpineStyleSpec.forTitle(titleId);

  Future<LabelContext> _context(TapeLabelData d, TextRecorder? recorder) async {
    // Palette from the poster, else from the background art, else curated.
    final art = d.poster ?? d.background;
    final results = await Future.wait<Object?>([
      TapePalette.resolve(d.titleId, art),
      LabelPrint.grainTile(),
      LabelPrint.speckleTile(),
      if (d.logo != null) LogoInfo.of(d.logo!) else Future<Object?>.value(null),
      if (d.poster != null) PosterSwatch.of(d.poster!) else Future<Object?>.value(null),
    ]);
    return LabelContext(
      data: d,
      palette: results[0]! as TapePalette,
      style: SpineStyleSpec.forTitle(d.titleId),
      grain: results[1]! as ui.Image,
      speckle: results[2]! as ui.Image,
      logoInfo: results[3] as LogoInfo?,
      posterDetail: (results[4] as PosterSwatch?)?.detail ?? 0,
      recorder: recorder,
    );
  }

  /// The resolved print context (palette, style, textures) for [d], for
  /// callers that want to time or drive [recordShelf]/[recordHero].
  @visibleForTesting
  Future<LabelContext> debugContext(TapeLabelData d) => _context(d, null);

  /// Shelf atlas: [widthPx] wide, height follows the 48 : 190.5 canvas.
  /// Regions: `spine` and `front_strip` (left 20 mm of the front cover).
  Future<ui.Image> composeShelf(TapeLabelData d, {int widthPx = 224}) async {
    final recorder = recordText ? TextRecorder() : null;
    final ctx = await _context(d, recorder);
    final layout = manifest.spine;
    final px = layout.pixelSizeForWidth(widthPx);
    final picture = recordShelf(ctx, px);
    final img = await picture.toImage(px.width.round(), px.height.round());
    picture.dispose();
    lastTextPlacements = recorder?.placements ?? const <TextPlacement>[];
    return img;
  }

  /// Hero atlas: square [sizePx], all five regions.
  Future<ui.Image> composeHero(TapeLabelData d, {int sizePx = 1536}) async {
    final recorder = recordText ? TextRecorder() : null;
    final ctx = await _context(d, recorder);
    final px = Size(sizePx.toDouble(), sizePx.toDouble());
    final picture = recordHero(ctx, px);
    final img = await picture.toImage(sizePx, sizePx);
    picture.dispose();
    lastTextPlacements = recorder?.placements ?? const <TextPlacement>[];
    return img;
  }

  /// Records the shelf atlas for [ctx] at [px] (synchronous part).
  ui.Picture recordShelf(LabelContext ctx, Size px) {
    final layout = manifest.spine;
    final design = layout.designSize;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Offset.zero & px);
    canvas.scale(px.width / design.width, px.height / design.height);
    SpinePainter.paint(canvas, layout.designRect('spine'), ctx);
    // The strip shows the left 20 mm of the full front cover.
    final strip = layout.designRect('front_strip');
    final front = Rect.fromLTWH(strip.left, strip.top,
        manifest.faceWidthMm * kUnitsPerMm, strip.height);
    canvas.save();
    canvas.clipRect(strip, doAntiAlias: false);
    // Text beyond the strip is clipped away; it is checked on the hero.
    FrontCoverPainter.paint(canvas, front, ctx.copyWith(dropRecorder: true));
    canvas.restore();
    return rec.endRecording();
  }

  /// Records the hero atlas for [ctx] at [px] (synchronous part).
  ui.Picture recordHero(LabelContext ctx, Size px) {
    final layout = manifest.hero;
    final design = layout.designSize;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Offset.zero & px);
    canvas.scale(px.width / design.width, px.height / design.height);
    BackCoverPainter.paint(canvas, layout.designRect('back'), ctx);
    SpinePainter.paint(canvas, layout.designRect('spine'), ctx);
    FrontCoverPainter.paint(canvas, layout.designRect('front'), ctx);
    CassettePainter.paintFace(canvas, layout.designRect('cassette_face'), ctx);
    CassettePainter.paintSpine(canvas, layout.designRect('cassette_spine'), ctx);
    return rec.endRecording();
  }
}
