import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/shelf/labels/label_text.dart';
import 'package:showtrack/shelf/labels/spine_painter.dart';
import 'package:showtrack/shelf/labels/spine_style.dart';
import 'package:showtrack/shelf/labels/title_fitter.dart';

import 'label_test_utils.dart';

const titles = <String>[
  'Ordinácia v ružovej záhrade',
  'Hviezdne vojny: Epizóda V – Impérium vracia úder',
  'Pán prsteňov: Spoločenstvo prsteňa',
  'Vesničko má středisková',
  'Tři oříšky pro Popelku',
  'Dark',
  'Lost',
  'Ľadová ťava ďaleko na Ôsmom kopci',
  'Kôň, Ďateľ & Čerešňa (1985)',
  'Šťastný Ůterý ve Žďáru',
  'Q',
  'Supercalifragilisticexpialidocious',
  'The Lord of the Rings: The Return of the King – Extended Edition Part II',
  'M*A*S*H',
  'Dr. Strangelove or: How I Learned to Stop Worrying and Love the Bomb',
];

final _style = SpineStyleSpec.forTitle('series-81189');

/// Title slots used by the composer, plus some deliberately awkward ones.
final specs = <String, (TitleFitSpec, List<Size>)>{
  'spine anton': (
    SpinePainter.antonSpec(_style),
    [const Size(990, 212), const Size(800, 212), const Size(500, 180)]
  ),
  'spine figtree': (SpinePainter.figtreeSpec(_style), [const Size(990, 200)]),
  'front strip': (
    const TitleFitSpec(
        maxFontSize: 58,
        minFontSize: 40,
        minFontSizeMultiLine: 24,
        maxLines: 2,
        mainAlign: TitleAlign.start),
    [const Size(520, 64), const Size(330, 64)]
  ),
  'cover': (
    const TitleFitSpec(
        maxFontSize: 230,
        minFontSize: 120,
        minFontSizeMultiLine: 80,
        maxLines: 4,
        mainAlign: TitleAlign.start,
        crossAlign: TitleAlign.end),
    [const Size(930, 640)]
  ),
  'tiny': (
    const TitleFitSpec(maxFontSize: 40, minFontSize: 20, maxLines: 2),
    [const Size(120, 30), const Size(60, 400), const Size(400, 12)]
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLabelFonts);

  test('no title ever overflows its box (model and real paragraphs)', () {
    var checked = 0;
    for (final e in specs.entries) {
      final (spec, boxes) = e.value;
      for (final box in boxes) {
        for (final t in titles) {
          final fit = TitleFitter.fit(t, box, spec);
          final why = '${e.key} $box "$t" → $fit';
          expect(fit.overflows, isFalse, reason: why);
          for (final line in fit.lines) {
            // Independent check: the real laid-out paragraph's ink width.
            final p = TitleFitter.paragraphFor(fit, line);
            final inkW = LabelText.inkWidth(p, fit.letterSpacing);
            expect(line.inkBox.left, greaterThanOrEqualTo(-0.01), reason: why);
            expect(line.inkBox.left + inkW, lessThanOrEqualTo(box.width + 0.01),
                reason: '$why: "${line.text}" is ${inkW.toStringAsFixed(2)} wide');
            expect((line.inkBox.width - inkW).abs(), lessThan(0.05), reason: why);
            expect(line.inkBox.top, greaterThanOrEqualTo(-0.01), reason: why);
            expect(line.inkBox.bottom, lessThanOrEqualTo(box.height + 0.01), reason: why);
          }
          checked++;
        }
      }
    }
    expect(checked, greaterThan(100));
  });

  test('predicted ink boxes contain the rendered glyph ink', () async {
    // Render each title big and find the actual ink rows/columns.
    const spec = TitleFitSpec(maxFontSize: 120, minFontSize: 60, maxLines: 2);
    for (final t in [
      'Šťastný Ůterý ve Žďáru',
      'Kôň, Ďateľ & Čerešňa (1985)',
      'Pán prsteňov: Spoločenstvo prsteňa',
      'QUIZ',
    ]) {
      const box = Size(2400, 320);
      final fit = TitleFitter.fit(t, box, spec);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      fit.paint(c, Offset.zero, color: const Color(0xFFFFFFFF));
      final pic = rec.endRecording();
      final img = await pic.toImage(box.width.toInt(), box.height.toInt());
      final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final bytes = data.buffer.asUint8List();
      final ink = _inkBounds(bytes, img.width, img.height);
      final predicted = fit.inkBounds;
      expect(ink, isNotNull);
      expect(ink!.top, greaterThanOrEqualTo(predicted.top - 1.5), reason: '$t top');
      expect(ink.bottom, lessThanOrEqualTo(predicted.bottom + 1.5), reason: '$t bottom');
      expect(ink.left, greaterThanOrEqualTo(predicted.left - 1.5), reason: '$t left');
      expect(ink.right, lessThanOrEqualTo(predicted.right + 1.5), reason: '$t right');
    }
  });

  test('very long titles break into two lines at the boundary nearest the middle', () {
    final spec = SpinePainter.antonSpec(_style);
    const box = Size(990, 212);
    final fit = TitleFitter.fit('Hviezdne vojny: Epizóda V – Impérium vracia úder', box, spec);
    expect(fit.stage, TitleFitStage.wrapped);
    expect(fit.lines.map((l) => l.text).toList(),
        ['HVIEZDNE VOJNY: EPIZÓDA V –', 'IMPÉRIUM VRACIA ÚDER']);

    // Nearest the middle among every legal boundary.
    final toks = TitleFitter.tokens('Hviezdne vojny: Epizóda V – Impérium vracia úder')
        .map((t) => t.toUpperCase())
        .toList();
    double w(String s) => TitleFitter.inkWidthOf(s, spec, 100, 0);
    final total = w(toks.join(' '));
    final chosen = w(fit.lines.first.text);
    for (var i = 1; i < toks.length; i++) {
      final alt = w(toks.sublist(0, i).join(' '));
      expect((chosen - total / 2).abs(), lessThanOrEqualTo((alt - total / 2).abs() + 1e-6));
    }

    final lotr = TitleFitter.fit('Pán prsteňov: Spoločenstvo prsteňa', box, spec);
    expect(lotr.lines.length, 2);
    expect(lotr.lines.first.text, 'PÁN PRSTEŇOV:');
  });

  test('short titles stay on one line at full size', () {
    final spec = SpinePainter.antonSpec(_style);
    for (final t in ['Dark', 'Lost']) {
      final fit = TitleFitter.fit(t, const Size(990, 212), spec);
      expect(fit.lines.length, 1);
      expect(fit.stage, TitleFitStage.fitted);
      expect(fit.lines.single.text, t.toUpperCase());
    }
  });

  test('ladder: shrink, then tighten tracking, then wrap, then ellipsis', () {
    const spec = TitleFitSpec(
        maxFontSize: 100, minFontSize: 50, minFontSizeMultiLine: 40,
        trackingEm: 0.02, minTrackingEm: -0.03, maxLines: 2);
    const text = 'TŘI OŘÍŠKY PRO POPELKU';
    // Shrunk: room for size 70 at preferred tracking.
    final shrunk = TitleFitter.fit(
        text, Size(TitleFitter.inkWidthOf(text, spec, 70, 0.02), 300), spec);
    expect(shrunk.stage, TitleFitStage.shrunk);
    expect(shrunk.fontSize, closeTo(70, 0.2));
    // Tightened: at the minimum size only tighter tracking fits.
    final tight = TitleFitter.fit(
        text, Size(TitleFitter.inkWidthOf(text, spec, 50, -0.01), 300), spec);
    expect(tight.stage, TitleFitStage.tightened);
    expect(tight.trackingEm, lessThan(0.02));
    expect(tight.trackingEm, greaterThanOrEqualTo(-0.03));
    // Wrapped: not even the tightest single line fits.
    final wrapped = TitleFitter.fit(
        text, Size(TitleFitter.inkWidthOf(text, spec, 50, -0.03) * 0.8, 300), spec);
    expect(wrapped.stage, TitleFitStage.wrapped);
    // Ellipsis: a single word that can't be broken.
    final ell = TitleFitter.fit('Supercalifragilisticexpialidocious', const Size(400, 120), spec);
    expect(ell.stage, TitleFitStage.ellipsized);
    expect(ell.lines.last.text.endsWith('…'), isTrue);
    expect(ell.overflows, isFalse);
  });

  test('diacritics are preserved and uppercased correctly', () {
    expect(TitleFitter.caseMap('Ordinácia v ružovej záhrade'), 'ORDINÁCIA V RUŽOVEJ ZÁHRADE');
    expect(TitleFitter.caseMap('Tři oříšky pro Popelku'), 'TŘI OŘÍŠKY PRO POPELKU');
    expect(TitleFitter.caseMap('Vesničko má středisková'), 'VESNIČKO MÁ STŘEDISKOVÁ');
    expect(TitleFitter.caseMap('ľ ť ď ň ô ä ŕ ĺ ř ů ě č š ž ý á í é ú ó'),
        'Ľ Ť Ď Ň Ô Ä Ŕ Ĺ Ř Ů Ě Č Š Ž Ý Á Í É Ú Ó');
    final spec = SpinePainter.antonSpec(_style);
    for (final t in titles.take(10)) {
      final fit = TitleFitter.fit(t, const Size(990, 212), spec);
      if (fit.ellipsized) continue;
      // Nothing dropped or substituted across the line break.
      expect(fit.lines.map((l) => l.text).join(' '), TitleFitter.caseMap(t));
    }
  });

  test('every Slovak/Czech capital renders from the bundled fonts', () {
    const caps = 'ÁÄČĎÉĚÍĹĽŇÓÔŔŘŠŤÚŮÝŽ';
    for (final (family, weight) in [
      (LabelFonts.display, FontWeight.w400),
      (LabelFonts.text, FontWeight.w800),
      (LabelFonts.text, FontWeight.w400),
    ]) {
      for (final ch in caps.split('')) {
        final p = LabelText.paragraph(ch, family: family, size: 100, weight: weight, cache: false);
        // The test fallback font draws 1 em squares; real glyphs are narrower.
        expect(p.maxIntrinsicWidth, lessThan(85), reason: '$family $ch');
      }
    }
  });

  test('break tokens keep prepositions and numerals attached', () {
    expect(TitleFitter.tokens('Ordinácia v ružovej záhrade'),
        ['Ordinácia', 'v ružovej', 'záhrade']);
    expect(TitleFitter.tokens('Hviezdne vojny: Epizóda V – Impérium vracia úder'),
        ['Hviezdne', 'vojny:', 'Epizóda V –', 'Impérium', 'vracia', 'úder']);
    expect(TitleFitter.tokens('Rocky II'), ['Rocky II']);
  });
}

Rect? _inkBounds(Uint8List rgba, int w, int h) {
  int? l, t, r, b;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] > 24) {
        l = l == null || x < l ? x : l;
        r = r == null || x > r ? x : r;
        t ??= y;
        b = y;
      }
    }
  }
  if (l == null) return null;
  return Rect.fromLTRB(l.toDouble(), t!.toDouble(), r! + 1.0, b! + 1.0);
}
