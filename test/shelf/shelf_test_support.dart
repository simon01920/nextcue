// Fixtures for the shelf tests: real fonts, a fixed tape source (no
// repository, no network) and simple deterministic spine art — a port of
// `spine_art` in tools/plates/composite.py — so the goldens test the plate
// compositor, layout and widgets, not the label composer's current look.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';
import 'package:showtrack/shelf/shelf_layout.dart';
import 'package:showtrack/shelf/tape_source.dart';

bool _fonts = false;

/// Anton + Figtree from assets/fonts (otherwise text renders as boxes).
Future<void> loadShelfFonts() async {
  if (_fonts) return;
  Future<ByteData> bytes(String f) async =>
      ByteData.view(Uint8List.fromList(
              await File('assets/fonts/$f').readAsBytes())
          .buffer);
  final anton = FontLoader('Anton')..addFont(bytes('Anton-Regular.ttf'));
  final figtree = FontLoader('Figtree');
  for (final w in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    figtree.addFont(bytes('Figtree-$w.ttf'));
  }
  await anton.load();
  await figtree.load();
  _fonts = true;
}

const List<String> sampleTitles = [
  'THE EXPANSE', 'Dark', 'Hra o tróny', 'SEVERANCE', 'Fargo', 'Twin Peaks',
  'Chernobyl', 'Kto chce byť milionárom?', 'Slnko v sieti', 'Breaking Bad',
  'Mr. Robot', 'Arcane', 'Stranger Things', 'Andor', 'Shōgun',
  'Better Call Saul', 'Ted Lasso', 'Mindhunter', 'The Bear', 'Westworld',
];

/// A [TapeSource] over a fixed title list.
class FixtureTapeSource extends ChangeNotifier implements TapeSource {
  FixtureTapeSource(this.titles, {this.states = const {}});

  /// titleId → title.
  final Map<String, String> titles;
  final Map<String, TapeState> states;

  TapeState _state(String id) =>
      states[id] ?? const TapeState(kind: TapeStateKind.completed);

  @override
  String labelKey(String titleId, {LabelUse use = LabelUse.shelf}) =>
      'fixture|${titles[titleId]}|${_state(titleId).cacheKey}';

  @override
  Future<LabelSnapshot?> labelData(String titleId,
      {LabelUse use = LabelUse.shelf, Duration? patience}) async {
    final t = titles[titleId];
    if (t == null) return null;
    return LabelSnapshot(
        TapeLabelData(titleId: titleId, title: t, state: _state(titleId)),
        labelKey(titleId));
  }

  @override
  String semanticsLabel(String titleId) => titles[titleId] ?? 'Tape';

  @override
  void prefetch(Iterable<String> titleIds) {}
}

const List<Color> _palette = [
  Color.fromARGB(255, 217, 31, 26), Color.fromARGB(255, 20, 26, 31),
  Color.fromARGB(255, 237, 227, 204), Color.fromARGB(255, 26, 77, 140),
  Color.fromARGB(255, 242, 179, 26), Color.fromARGB(255, 38, 115, 71),
  Color.fromARGB(255, 115, 26, 89), Color.fromARGB(255, 235, 115, 38),
  Color.fromARGB(255, 51, 51, 56), Color.fromARGB(255, 179, 191, 204),
];

/// Spine atlas like composite.py's test art: colour field, accent bands,
/// the title reading top-to-bottom, a gradient front strip.
Future<ui.Image> fixtureSpineArt(TapeLabelData d, int widthPx) async {
  const canvasW = 48.0, canvasH = 190.5, spineFrac = 0.5833333333333334;
  final w = widthPx.toDouble();
  final h = (widthPx * canvasH / canvasW).roundToDouble();
  final seed = ShelfLayout.variantSeed(d.titleId);
  final n = _palette.length;
  final bg = _palette[seed % n];
  var ai = (seed ~/ n) % n;
  if (ai == seed % n) ai = (ai + 3) % n;
  final accent = _palette[ai];
  final fg = bg.computeLuminance() < 0.35
      ? const Color(0xFFF5F2EB)
      : const Color(0xFF0F0F12);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final sw = w * spineFrac;
  c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = bg);
  c.drawRect(Rect.fromLTWH(0, 0, sw, h * 0.09), Paint()..color = accent);
  c.drawRect(Rect.fromLTRB(0, h * 0.93, sw, h), Paint()..color = accent);
  // Front strip: accent fading to a darkened field.
  c.drawRect(
      Rect.fromLTRB(sw, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset(sw, 0), Offset(sw, h),
            [accent, Color.lerp(bg, const Color(0xFF000000), 0.4)!]));
  // Title, reading top-to-bottom, fitted to 78 % of the length.
  final len = h * 0.78;
  var size = sw * 0.52;
  ui.Paragraph para;
  for (;;) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1))
      ..pushStyle(ui.TextStyle(
          color: fg, fontFamily: 'Anton', fontSize: size, height: 1.0))
      ..addText(d.title.toUpperCase());
    para = b.build()..layout(const ui.ParagraphConstraints(width: 1e5));
    if (para.maxIntrinsicWidth <= len * 0.95 || size < 8) break;
    size -= 1;
  }
  c.save();
  c.translate(sw / 2 + para.height / 2, h * 0.11 + (len - para.maxIntrinsicWidth) / 2);
  c.rotate(1.5707963267948966);
  c.drawParagraph(para, Offset.zero);
  c.restore();
  final pic = rec.endRecording();
  final img = await pic.toImage(w.round(), h.round());
  pic.dispose();
  return img;
}

/// PNG bytes of [img].
Future<Uint8List> pngOf(ui.Image img) async =>
    (await img.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();

/// A real-asset bundle for plain `test()`s (rootBundle works there too).
AssetBundle get testBundle => rootBundle;

/// A hero atlas stand-in: one colour field per region, the title on the
/// spine and the front.
Future<ui.Image> fixtureHeroArt(TapeLabelData d, int sizePx) async {
  final n = sizePx.toDouble();
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, n, n), Paint()..color = const Color(0xFFE6E2D8));
  const regions = {
    'back': Rect.fromLTWH(0.0, 0.0, 0.41796875, 0.744140625),
    'spine': Rect.fromLTWH(0.41796875, 0.0, 0.109375, 0.744140625),
    'front': Rect.fromLTWH(0.52734375, 0.0, 0.41796875, 0.744140625),
    'cassette_face': Rect.fromLTWH(0.0, 0.76953125, 0.30859375, 0.16796875),
    'cassette_spine': Rect.fromLTWH(0.3359375, 0.76953125, 0.57421875, 0.07421875),
  };
  final seed = ShelfLayout.variantSeed(d.titleId);
  var i = 0;
  for (final e in regions.entries) {
    final r = e.value;
    c.drawRect(Rect.fromLTWH(r.left * n, r.top * n, r.width * n, r.height * n),
        Paint()..color = _palette[(seed + i++) % _palette.length]);
  }
  final front = regions['front']!;
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
    ..pushStyle(ui.TextStyle(
        color: const Color(0xFFFFFFFF), fontFamily: 'Anton', fontSize: n * 0.04))
    ..addText(d.title.toUpperCase());
  final p = b.build()..layout(ui.ParagraphConstraints(width: front.width * n));
  c.drawParagraph(p, Offset(front.left * n, front.height * n * 0.75));
  final pic = rec.endRecording();
  final img = await pic.toImage(sizePx, sizePx);
  pic.dispose();
  return img;
}
