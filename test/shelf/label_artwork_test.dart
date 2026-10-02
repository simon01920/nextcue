// Artwork mapping: which TVDB image lands on which printed surface, and the
// fallbacks when an image is missing.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/shelf/labels/atlas_layout.dart';
import 'package:showtrack/shelf/labels/label_art.dart';
import 'package:showtrack/shelf/labels/label_composer.dart';
import 'package:showtrack/shelf/labels/label_text.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';

import 'label_test_utils.dart';

Future<ui.Image> _solid(int w, int h, Color c) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w * 1.0, h * 1.0), Paint()..color = c);
  return rec.endRecording().toImage(w, h);
}

/// An opaque 4:1 bar with transparent margins all round (like many TVDB
/// clear logos).
Future<ui.Image> _barLogo(Color c) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(const Rect.fromLTWH(100, 100, 400, 100), Paint()..color = c);
  return rec.endRecording().toImage(600, 300);
}

Future<Color> _pixel(ui.Image img, double x, double y) async {
  final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final o = (y.round() * img.width + x.round()) * 4;
  return Color.fromARGB(d.getUint8(o + 3), d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2));
}

int _r(Color c) => (c.r * 255).round();
int _g(Color c) => (c.g * 255).round();
int _b(Color c) => (c.b * 255).round();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLabelFonts);
  final hero = AtlasManifest.standard.hero;
  const px = Size(512, 512);

  group('logo analysis', () {
    test('ink bounds trim transparent margins; mean colour is alpha-weighted', () {
      // 8×4 premultiplied thumbnail: opaque red at x 2..5, y 1..2.
      final bytes = Uint8List(8 * 4 * 4);
      for (var y = 1; y <= 2; y++) {
        for (var x = 2; x <= 5; x++) {
          final o = (y * 8 + x) * 4;
          bytes[o] = 200;
          bytes[o + 3] = 255;
        }
      }
      final info = LogoInfo.fromRgba(bytes, width: 8);
      expect(info.bounds.left, closeTo(1 / 8, 1e-9));
      expect(info.bounds.right, closeTo(7 / 8, 1e-9));
      expect(info.bounds.top, closeTo(0, 1e-9));
      expect(info.bounds.bottom, closeTo(4 / 4, 1e-9));
      expect(_r(info.meanColor), 200);
      expect(_g(info.meanColor), 0);
    });

    test('a logo that would vanish into the ground gets a keyline', () {
      const dark = LogoInfo(meanColor: Color(0xFF1A1A22), coverage: 0.5);
      const light = LogoInfo(meanColor: Color(0xFFF2EEE6), coverage: 0.5);
      const ink = Color(0xFF151413), paper = Color(0xFFF2ECDF);
      expect(LabelArt.treatmentFor(dark, ink), LogoTreatment.keyline);
      expect(LabelArt.treatmentFor(light, ink), LogoTreatment.asIs);
      expect(LabelArt.treatmentFor(light, paper), LogoTreatment.keyline);
      expect(LabelArt.treatmentFor(dark, paper), LogoTreatment.asIs);
    });
  });

  group('surface mapping', () {
    late TapeLabelData full;
    setUpAll(() async {
      full = TapeLabelData(
        titleId: 'series-mapping-1',
        title: 'Testovací titul',
        year: '1999',
        poster: await _solid(680, 1000, const Color(0xFF00C000)),
        background: await _solid(960, 540, const Color(0xFFD000D0)),
        banner: await _solid(758, 140, const Color(0xFF00C0E0)),
        logo: await _barLogo(const Color(0xFFFFFFFF)),
        synopsis: 'Krátky popis.',
        state: const TapeState(kind: TapeStateKind.watching, progress: 0.5, watched: 2, total: 4),
      );
    });

    test('poster → front, background → back + cassette face, banner → cassette spine',
        () async {
      final img = await LabelComposer().composeHero(full, sizePx: 512);
      final front = hero.pixelRect('front', px);
      final c1 = await _pixel(img, front.center.dx, front.top + front.height * 0.45);
      expect(_g(c1) - _r(c1) > 60 && _g(c1) - _b(c1) > 60, isTrue, reason: 'front $c1 not the green poster');

      // Back main image: design (66..1004, ≥330) → upper-middle of the back.
      final back = hero.pixelRect('back', px);
      final c2 = await _pixel(img, back.center.dx, back.top + back.height * 0.26);
      expect(_r(c2) - _g(c2) > 60 && _b(c2) - _g(c2) > 60, isTrue,
          reason: 'back $c2 not the magenta background');

      final face = hero.pixelRect('cassette_face', px);
      final c3 = await _pixel(img, face.left + face.width * 0.5, face.top + face.height * 0.3);
      expect(_r(c3) - _g(c3) > 50 && _b(c3) - _g(c3) > 50, isTrue,
          reason: 'cassette face $c3 not the background crop');

      final cspine = hero.pixelRect('cassette_spine', px);
      final c4 = await _pixel(img, cspine.left + cspine.width * 0.2, cspine.center.dy);
      expect(_b(c4) - _r(c4) > 60 && _g(c4) - _r(c4) > 60, isTrue,
          reason: 'cassette spine $c4 not the cyan banner');
    });

    test('spine prints the clear logo rotated, aspect kept, instead of the title', () async {
      final composer = LabelComposer(recordText: true);
      await composer.composeShelf(full, widthPx: 224);
      final spine = composer.lastTextPlacements.where((p) => p.region == 'spine').toList();
      final logos = spine.where((p) => p.text == '[logo]').toList();
      expect(logos, hasLength(1));
      final r = logos.single.rect;
      // A 4:1 logo turned +90°: the footprint is ~4× taller than wide.
      expect(r.height / r.width, closeTo(4, 0.8));
      expect(spine.any((p) => p.text.contains('TESTOVACÍ')), isFalse);
      // …and the title type comes back when the logo is missing.
      await composer.composeShelf(full.copyWith(clearLogo: true), widthPx: 224);
      expect(
          composer.lastTextPlacements
              .any((p) => p.region == 'spine' && p.text.contains('TESTOVACÍ')),
          isTrue);
    });

    test('logo never goes over a real poster, only makes poster-less covers',
        () async {
      final photos = await PhotoTapes.all();
      final composer = LabelComposer(recordText: true);
      bool frontLogo(List<TextPlacement> ps) =>
          ps.any((p) => p.region == 'front' && p.text == '[logo]');
      await composer.composeHero(photos['busy_poster']!, sizePx: 512);
      expect(frontLogo(composer.lastTextPlacements), isFalse);
      await composer.composeHero(photos['full_art']!, sizePx: 512);
      expect(frontLogo(composer.lastTextPlacements), isFalse);
      // No poster: background + logo make the cover.
      await composer.composeHero(photos['no_poster']!, sizePx: 512);
      expect(frontLogo(composer.lastTextPlacements), isTrue);
    });

    test('every combination of missing artwork composes, opaque, text in bounds',
        () async {
      final composer = LabelComposer(recordText: true);
      final variants = <String, TapeLabelData>{
        'none': full.copyWith(
            clearPoster: true, clearLogo: true, clearBanner: true, clearBackground: true),
        'logo only': full.copyWith(clearPoster: true, clearBanner: true, clearBackground: true),
        'banner only': full.copyWith(clearPoster: true, clearLogo: true, clearBackground: true),
        'background only': full.copyWith(clearPoster: true, clearLogo: true, clearBanner: true),
        'poster only': full.copyWith(clearLogo: true, clearBanner: true, clearBackground: true),
        'all': full,
      };
      for (final e in variants.entries) {
        final img = await composer.composeHero(e.value, sizePx: 512);
        final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        for (final region in hero.regions.values) {
          final r = region.rectIn(px);
          for (var y = r.top.ceil(); y < r.bottom.floor(); y += 5) {
            for (var x = r.left.ceil(); x < r.right.floor(); x += 5) {
              expect(d.getUint8((y * 512 + x) * 4 + 3), 255,
                  reason: '${e.key}: ${region.name} ($x,$y) not opaque');
            }
          }
        }
        for (final p in composer.lastTextPlacements) {
          final r = hero.pixelRect(p.region, px).inflate(0.75);
          expect(r.contains(p.rect.topLeft) && r.contains(p.rect.bottomRight - const Offset(0.001, 0.001)),
              isTrue,
              reason: '${e.key}: "${p.text}" ${p.rect} leaves ${p.region}');
        }
      }
    });
  });
}
