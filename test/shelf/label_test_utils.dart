// Shared fixtures for the label composer tests: real fonts, procedurally
// painted stand-in posters (tests have no network) and sample tapes.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:showtrack/shelf/labels/label_rng.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';

bool _fontsLoaded = false;

/// Loads Anton and every Figtree weight from assets/fonts — without this
/// the test engine renders text as Ahem boxes.
Future<void> loadLabelFonts() async {
  if (_fontsLoaded) return;
  Future<ByteData> bytes(String f) async {
    final b = await File('assets/fonts/$f').readAsBytes();
    return ByteData.view(Uint8List.fromList(b).buffer);
  }

  final anton = FontLoader('Anton')..addFont(bytes('Anton-Regular.ttf'));
  final figtree = FontLoader('Figtree');
  for (final w in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    figtree.addFont(bytes('Figtree-$w.ttf'));
  }
  await anton.load();
  await figtree.load();
  _fontsLoaded = true;
}

const int posterW = 680, posterH = 1000;

Future<ui.Image> _render(int w, int h, void Function(Canvas c, Size s) paint) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  paint(c, Size(w.toDouble(), h.toDouble()));
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  pic.dispose();
  return img;
}

ui.Paragraph _para(String text, double size,
    {String family = 'Figtree',
    FontWeight weight = FontWeight.w800,
    double spacing = 0,
    Color color = const Color(0xFFFFFFFF),
    double width = 2000,
    TextAlign align = TextAlign.left}) {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: align))
    ..pushStyle(ui.TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color))
    ..addText(text);
  return b.build()..layout(ui.ParagraphConstraints(width: width));
}

void _centered(Canvas c, Size s, String text, double y, double size,
    {String family = 'Figtree',
    FontWeight weight = FontWeight.w800,
    double spacing = 0,
    Color color = const Color(0xFFFFFFFF)}) {
  final p = _para(text, size,
      family: family,
      weight: weight,
      spacing: spacing,
      color: color,
      width: s.width,
      align: TextAlign.center);
  c.drawParagraph(p, Offset(0, y));
}

void _stars(Canvas c, Size s, int seed, int n, {double maxY = 1}) {
  final r = LabelRng(seed);
  final small = <double>[], big = <double>[];
  for (var i = 0; i < n; i++) {
    final x = r.nextDouble() * s.width, y = r.nextDouble() * s.height * maxY;
    (r.chance(0.15) ? big : small)
      ..add(x)
      ..add(y);
  }
  final p = Paint()
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xCCFFFFFF);
  c.drawRawPoints(ui.PointMode.points, Float32List.fromList(small), p..strokeWidth = 1.6);
  c.drawRawPoints(ui.PointMode.points, Float32List.fromList(big), p..strokeWidth = 3.2);
}

/// Space opera: starfield, ringed planet, light-sword streaks, yellow title.
Future<ui.Image> posterSpace() => _render(posterW, posterH, (c, s) {
      final full = Offset.zero & s;
      c.drawRect(
          full,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height),
                const [Color(0xFF02030A), Color(0xFF0B1230), Color(0xFF1B0F2E)], const [0, 0.6, 1]));
      _stars(c, s, 7, 420);
      // Nebula glow.
      c.drawCircle(
          Offset(s.width * 0.3, s.height * 0.35),
          340,
          Paint()
            ..shader = ui.Gradient.radial(Offset(s.width * 0.3, s.height * 0.35), 340,
                const [Color(0x553A6BFF), Color(0x00000000)]));
      // Planet.
      final pc = Offset(s.width * 0.72, s.height * 0.86);
      c.drawCircle(
          pc,
          330,
          Paint()
            ..shader = ui.Gradient.radial(pc.translate(-120, -140), 520,
                const [Color(0xFFF6B26B), Color(0xFFB4462A), Color(0xFF2A0C10)], const [0, 0.45, 1]));
      c.save();
      c.translate(pc.dx, pc.dy);
      c.rotate(-0.35);
      c.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 900, height: 120),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..color = const Color(0x99FFD9A0));
      c.restore();
      // Two light swords crossing.
      void sword(Offset a, Offset b, Color col) {
        c.drawLine(
            a,
            b,
            Paint()
              ..color = col.withValues(alpha: 0.5)
              ..strokeWidth = 26
              ..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
        c.drawLine(
            a,
            b,
            Paint()
              ..color = const Color(0xFFFFFFFF)
              ..strokeWidth = 7
              ..strokeCap = StrokeCap.round);
      }

      sword(Offset(s.width * 0.12, s.height * 0.62), Offset(s.width * 0.62, s.height * 0.2),
          const Color(0xFFFF2B2B));
      sword(Offset(s.width * 0.88, s.height * 0.6), Offset(s.width * 0.36, s.height * 0.22),
          const Color(0xFF3BA0FF));
      // Dark helmet silhouette.
      final helmet = Path()
        ..moveTo(s.width * 0.5 - 120, s.height * 0.62)
        ..quadraticBezierTo(s.width * 0.5 - 130, s.height * 0.42, s.width * 0.5, s.height * 0.4)
        ..quadraticBezierTo(s.width * 0.5 + 130, s.height * 0.42, s.width * 0.5 + 120, s.height * 0.62)
        ..lineTo(s.width * 0.5 + 170, s.height * 0.7)
        ..lineTo(s.width * 0.5 - 170, s.height * 0.7)
        ..close();
      c.drawPath(helmet, Paint()..color = const Color(0xFF07070B));
      _centered(c, s, 'HVIEZDNE VOJNY', 64, 64,
          family: 'Anton', weight: FontWeight.w400, spacing: 3, color: const Color(0xFFFFD84A));
      _centered(c, s, 'IMPÉRIUM VRACIA ÚDER', 150, 26, spacing: 8, color: const Color(0xFFFFE8A0));
    });

/// Fantasy: smouldering sky, mountains, a golden ring.
Future<ui.Image> posterRing() => _render(posterW, posterH, (c, s) {
      final full = Offset.zero & s;
      c.drawRect(
          full,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height),
                const [Color(0xFF120A06), Color(0xFF6B2A0E), Color(0xFFD9822B), Color(0xFF1A0E08)],
                const [0, 0.42, 0.6, 1]));
      // Mountains.
      final r = LabelRng(31);
      for (var layer = 0; layer < 3; layer++) {
        final base = s.height * (0.62 + layer * 0.1);
        final path = Path()..moveTo(0, s.height);
        var x = 0.0;
        path.lineTo(0, base);
        while (x < s.width) {
          x += r.range(50, 130);
          path.lineTo(x, base - r.range(40, 200) * (1 - layer * 0.25));
        }
        path
          ..lineTo(s.width, s.height)
          ..close();
        c.drawPath(path, Paint()..color = Color.lerp(const Color(0xFF3A1A0C), const Color(0xFF0A0604), layer / 2)!);
      }
      // Ring.
      final rc = Offset(s.width / 2, s.height * 0.36);
      c.drawCircle(
          rc,
          250,
          Paint()
            ..shader = ui.Gradient.radial(rc, 250, const [Color(0x66FFB347), Color(0x00FFB347)]));
      c.drawCircle(
          rc,
          120,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 30
            ..shader = ui.Gradient.sweep(rc, const [
              Color(0xFFFFE9A8),
              Color(0xFFB8860B),
              Color(0xFFFFD36B),
              Color(0xFF8A5A0A),
              Color(0xFFFFE9A8),
            ], const [0, 0.25, 0.5, 0.75, 1]));
      _centered(c, s, 'PÁN PRSTEŇOV', s.height - 190, 58,
          weight: FontWeight.w300, spacing: 10, color: const Color(0xFFF3D27A));
      _centered(c, s, 'SPOLOČENSTVO PRSTEŇA', s.height - 112, 24,
          weight: FontWeight.w600, spacing: 9, color: const Color(0xFFE8C88A));
    });

/// Hospital drama: rose pink, bokeh, a big stylised rose.
Future<ui.Image> posterRose() => _render(posterW, posterH, (c, s) {
      final full = Offset.zero & s;
      c.drawRect(
          full,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(s.width, s.height),
                const [Color(0xFFFFD1DC), Color(0xFFF06292), Color(0xFF8E1B47)],
                const [0, 0.5, 1]));
      final r = LabelRng(77);
      for (var i = 0; i < 26; i++) {
        c.drawCircle(Offset(r.nextDouble() * s.width, r.nextDouble() * s.height),
            r.range(20, 90), Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: r.range(0.06, 0.2)));
      }
      final rc = Offset(s.width * 0.5, s.height * 0.42);
      for (var i = 0; i < 9; i++) {
        final a = i * 0.9;
        final rr = 210 - i * 20.0;
        c.drawCircle(
            rc + Offset(math.cos(a) * 18, math.sin(a) * 18),
            rr,
            Paint()
              ..color = Color.lerp(const Color(0xFFB0123E), const Color(0xFFFF6F91), i / 8)!
              ..style = i.isEven ? PaintingStyle.fill : PaintingStyle.stroke
              ..strokeWidth = 10);
      }
      // White cross.
      final cross = Paint()..color = const Color(0xFFFFFFFF);
      c.drawRect(Rect.fromCenter(center: Offset(s.width * 0.82, s.height * 0.12), width: 70, height: 22), cross);
      c.drawRect(Rect.fromCenter(center: Offset(s.width * 0.82, s.height * 0.12), width: 22, height: 70), cross);
      _centered(c, s, 'ORDINÁCIA', s.height - 210, 76, family: 'Anton', weight: FontWeight.w400, spacing: 2);
      _centered(c, s, 'v ružovej záhrade', s.height - 104, 34, weight: FontWeight.w500, spacing: 1);
    });

/// Winter fairy tale: pale sky, snowfall, pines, three hazelnuts.
Future<ui.Image> posterSnow() => _render(posterW, posterH, (c, s) {
      final full = Offset.zero & s;
      c.drawRect(
          full,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height),
                const [Color(0xFF9CC3E6), Color(0xFFE4F0FA), Color(0xFFFFFFFF)], const [0, 0.55, 1]));
      final r = LabelRng(5);
      for (var i = 0; i < 14; i++) {
        final x = r.nextDouble() * s.width;
        final h = r.range(160, 340);
        final base = s.height * r.range(0.56, 0.66);
        c.drawPath(
            Path()
              ..moveTo(x, base - h)
              ..lineTo(x + h * 0.28, base)
              ..lineTo(x - h * 0.28, base)
              ..close(),
            Paint()..color = Color.lerp(const Color(0xFF1E4D3A), const Color(0xFF6E8FA3), r.nextDouble() * 0.6)!);
      }
      c.drawRect(Rect.fromLTRB(0, s.height * 0.64, s.width, s.height), Paint()..color = const Color(0xFFF7FBFF));
      // Hazelnuts.
      for (var i = 0; i < 3; i++) {
        final ct = Offset(s.width * (0.32 + i * 0.18), s.height * 0.76 + (i == 1 ? -16 : 0));
        c.drawOval(Rect.fromCenter(center: ct, width: 92, height: 104),
            Paint()..color = const Color(0xFF8A4B1F));
        c.drawOval(Rect.fromCenter(center: ct.translate(0, -34), width: 70, height: 34),
            Paint()..color = const Color(0xFFC9A36B));
      }
      _stars(c, s, 99, 260);
      _centered(c, s, 'Tři oříšky pro Popelku', 70, 50,
          weight: FontWeight.w700, color: const Color(0xFF7A1630));
    });

/// Mystery: dark forest, a cave mouth.
Future<ui.Image> posterForest() => _render(posterW, posterH, (c, s) {
      final full = Offset.zero & s;
      c.drawRect(
          full,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height),
                const [Color(0xFF1B2A26), Color(0xFF3E4F45), Color(0xFF0C110F)], const [0, 0.5, 1]));
      // Cave mouth with a cold light.
      final cc = Offset(s.width / 2, s.height * 0.55);
      c.drawCircle(cc, 210, Paint()..shader = ui.Gradient.radial(cc, 210, const [Color(0xFFD8E6E0), Color(0xFF55675F), Color(0x0055675F)], const [0, 0.35, 1]));
      for (var i = 0; i < 5; i++) {
        c.drawCircle(
            cc,
            90.0 + i * 34,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6
              ..color = const Color(0xFF0A0F0D).withValues(alpha: 0.5));
      }
      final r = LabelRng(13);
      for (var i = 0; i < 18; i++) {
        final x = r.nextDouble() * s.width;
        final w = r.range(14, 34);
        c.drawRect(Rect.fromLTWH(x, 0, w, s.height), Paint()..color = const Color(0xFF070B09).withValues(alpha: r.range(0.55, 0.95)));
      }
      // Lone figure.
      c.drawRect(Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.78), width: 22, height: 90),
          Paint()..color = const Color(0xFFB3261E));
    });

/// Clear logo: transparent PNG-like wordmark.
Future<ui.Image> logoDark() => _render(600, 180, (c, s) {
      final p = _para('D A R K', 120,
          weight: FontWeight.w300, spacing: 18, color: const Color(0xFFF2F2EE), width: s.width, align: TextAlign.center);
      c.drawParagraph(p, Offset(0, (s.height - p.height) / 2));
    });

/// Disaster drama: teal sky, cooling tower, plume.
Future<ui.Image> posterTower() => _render(posterW, posterH, (c, s) {
      c.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height),
                const [Color(0xFF2E4A47), Color(0xFF8FA58A), Color(0xFF1C2622)], const [0, 0.55, 1]));
      for (var i = 0; i < 8; i++) {
        c.drawCircle(Offset(s.width * 0.42 + i * 24, s.height * 0.42 - i * 50), 90.0 + i * 16,
            Paint()
              ..color = const Color(0xFFDCE3D2).withValues(alpha: 0.18)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
      }
      final tower = Path()
        ..moveTo(s.width * 0.3, s.height)
        ..quadraticBezierTo(s.width * 0.4, s.height * 0.7, s.width * 0.35, s.height * 0.5)
        ..lineTo(s.width * 0.6, s.height * 0.5)
        ..quadraticBezierTo(s.width * 0.55, s.height * 0.7, s.width * 0.68, s.height)
        ..close();
      c.drawPath(tower, Paint()..color = const Color(0xFF141B18));
      _centered(c, s, 'CHERNOBYL', s.height - 150, 70,
          family: 'Anton', weight: FontWeight.w400, spacing: 12, color: const Color(0xFFE8E4D0));
    });

// ── Photographic stand-ins ───────────────────────────────────────────────
// Real TVDB art can't be fetched in tests, so these paint images with the
// statistics of photographs: smooth sky gradients, a bloom around the sun,
// atmospheric perspective (farther ridges lighter and softer), a blurred
// water reflection, defocused foreground and film grain.

/// Records the sky of a dusk landscape (shared by the photo and its
/// reflection).
ui.Picture _skyPicture(Size s, List<Color> sky, Offset sun) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height), sky,
            [for (var i = 0; i < sky.length; i++) i / (sky.length - 1)]));
  // Bloom.
  c.drawCircle(
      sun,
      s.width * 0.45,
      Paint()
        ..shader = ui.Gradient.radial(sun, s.width * 0.45,
            const [Color(0xCCFFE2B0), Color(0x33FFB27A), Color(0x00FFB27A)], const [0, 0.35, 1]));
  // Soft cloud banks.
  final r = LabelRng(91);
  for (var i = 0; i < 9; i++) {
    final cy = s.height * r.range(0.08, 0.42);
    c.drawOval(
        Rect.fromCenter(
            center: Offset(s.width * r.range(-0.1, 1.1), cy),
            width: s.width * r.range(0.35, 0.8),
            height: s.height * r.range(0.025, 0.06)),
        Paint()
          ..color = Color.lerp(const Color(0xFFFFC7A8), const Color(0xFF6B4A78), cy / (s.height * 0.42))!
              .withValues(alpha: r.range(0.25, 0.55))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * 0.012));
  }
  c.drawCircle(sun, s.width * 0.035,
      Paint()
        ..color = const Color(0xFFFFF6E0)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * 0.004));
  return rec.endRecording();
}

void _grain(Canvas c, Size s, int seed, {double amount = 0.06}) {
  final r = LabelRng(seed);
  final light = <double>[], dark = <double>[];
  final n = (s.width * s.height / 9).round();
  for (var i = 0; i < n; i++) {
    (r.chance(0.5) ? light : dark)
      ..add(r.nextDouble() * s.width)
      ..add(r.nextDouble() * s.height);
  }
  final p = Paint()..strokeWidth = 1.2;
  c.drawRawPoints(ui.PointMode.points, Float32List.fromList(light),
      p..color = Color.fromRGBO(255, 255, 255, amount));
  c.drawRawPoints(ui.PointMode.points, Float32List.fromList(dark),
      p..color = Color.fromRGBO(0, 0, 0, amount * 1.3));
}

/// A dusk lake landscape, [w]×[h], seeded so variants differ.
void paintLandscape(Canvas c, Size s, {int seed = 1, double horizon = 0.62, bool water = true}) {
  final sky = [
    const Color(0xFF1B2447),
    const Color(0xFF5B3D6E),
    const Color(0xFFD9785A),
    const Color(0xFFFFC98E),
  ];
  final hy = s.height * horizon;
  final sun = Offset(s.width * 0.63, hy - s.height * 0.07);
  final skyPic = _skyPicture(Size(s.width, hy), sky, sun);
  c.drawPicture(skyPic);
  // Ridges: far → near, lighter and softer with distance.
  final r = LabelRng(seed * 7 + 3);
  const haze = Color(0xFFB9766E), near = Color(0xFF130E1A);
  for (var layer = 0; layer < 4; layer++) {
    final t = layer / 3;
    final base = hy - s.height * (0.06 - layer * 0.012);
    final path = Path()..moveTo(-10, hy + 2);
    var x = -10.0;
    var y = base - s.height * r.range(0.02, 0.12);
    path.lineTo(x, y);
    while (x < s.width + 10) {
      x += s.width * r.range(0.015, 0.05);
      y = (y + s.height * r.jitter(0.025)).clamp(base - s.height * (0.2 - layer * 0.03), base);
      path.lineTo(x, y);
    }
    path
      ..lineTo(s.width + 10, hy + 2)
      ..close();
    final paint = Paint()..color = Color.lerp(haze, near, 0.25 + t * 0.75)!;
    if (layer < 2) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * (0.003 - layer * 0.0012));
    }
    c.drawPath(path, paint);
  }
  if (water) {
    // Water: the sky mirrored, blurred and darkened.
    final wr = Rect.fromLTRB(0, hy, s.width, s.height);
    c.save();
    c.clipRect(wr);
    c.saveLayer(wr, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: s.width * 0.002, sigmaY: s.height * 0.012));
    c.translate(0, hy * 2);
    c.scale(1, -1);
    c.drawPicture(skyPic);
    c.restore();
    c.drawRect(
        wr,
        Paint()
          ..shader = ui.Gradient.linear(wr.topCenter, wr.bottomCenter,
              const [Color(0x66101828), Color(0xEE0B0E16)]));
    // Glints.
    final g = <double>[];
    for (var i = 0; i < 260; i++) {
      final yy = hy + (s.height - hy) * math.pow(r.nextDouble(), 2).toDouble();
      final spread = s.width * 0.03 + (yy - hy) * 0.35;
      g.addAll([sun.dx + r.jitter(spread), yy]);
    }
    c.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(g),
        Paint()
          ..color = const Color(0xAAFFE0B0)
          ..strokeWidth = s.width * 0.002
          ..strokeCap = StrokeCap.round);
    c.restore();
  } else {
    c.drawRect(Rect.fromLTRB(0, hy, s.width, s.height), Paint()..color = near);
  }
  // Defocused foreground reeds.
  final reeds = Paint()
    ..color = const Color(0xFF07060A)
    ..strokeCap = StrokeCap.round
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * 0.0025);
  for (var i = 0; i < 70; i++) {
    final x = s.width * r.nextDouble();
    final top = s.height * r.range(0.72, 0.95);
    reeds.strokeWidth = s.width * r.range(0.002, 0.006);
    c.drawLine(Offset(x, s.height + 5), Offset(x + r.jitter(s.width * 0.03), top), reeds);
  }
  _grain(c, s, seed);
  LabelPrintTestVignette.paint(c, s);
}

/// Landscape fanart, 16:9 (TVDB backgrounds are 1920×1080; half size here).
Future<ui.Image> photoBackground({int seed = 1}) =>
    _render(960, 540, (c, s) => paintLandscape(c, s, seed: seed));

/// A photographic key-art poster: the landscape, a lone figure with a rim
/// of light, the title set in the sky and a credits block.
Future<ui.Image> photoPoster() => _render(posterW, posterH, (c, s) {
      paintLandscape(c, s, seed: 4, horizon: 0.66);
      // Figure on the shore, rim-lit.
      final f = Path()
        ..addOval(Rect.fromCenter(center: Offset(s.width * 0.36, s.height * 0.6), width: 30, height: 36))
        ..moveTo(s.width * 0.36 - 34, s.height * 0.72)
        ..quadraticBezierTo(s.width * 0.36 - 30, s.height * 0.615, s.width * 0.36, s.height * 0.615)
        ..quadraticBezierTo(s.width * 0.36 + 30, s.height * 0.615, s.width * 0.36 + 34, s.height * 0.72)
        ..close();
      c.drawPath(
          f,
          Paint()
            ..color = const Color(0xFFFFB878)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      c.drawPath(f, Paint()..color = const Color(0xFF0A0810));
      _centered(c, s, 'SLNKO V SIETI', 70, 74,
          family: 'Anton', weight: FontWeight.w400, spacing: 6, color: const Color(0xFFFFF1DC));
      _centered(c, s, 'FILM  ŠTEFANA  UHERA', 172, 20, weight: FontWeight.w600, spacing: 8,
          color: const Color(0xCCFFE6CC));
      // Billing block.
      for (var i = 0; i < 3; i++) {
        _centered(c, s, 'MARIÁN BIELIK  ·  JANA BELÁKOVÁ  ·  ELIŠKA NOSÁLOVÁ  ·  ANDREJ VANDLÍK', s.height - 92 + i * 18.0, 11,
            weight: FontWeight.w500, spacing: 1.5, color: const Color(0x99FFFFFF));
      }
    });

/// A busy collage poster (many tiles of different art, lots of edges).
Future<ui.Image> posterCollage() async {
  final bg = await photoBackground(seed: 9);
  return _render(posterW, posterH, (c, s) {
    final r = LabelRng(33);
    const cols = 5, rows = 7;
    final tw = s.width / cols, th = s.height / rows;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final dst = Rect.fromLTWH(x * tw, y * th, tw, th).deflate(2);
        final sx = r.range(0, bg.width - 160.0), sy = r.range(0, bg.height - 220.0);
        c.drawImageRect(bg, Rect.fromLTWH(sx, sy, 160, 220), dst,
            Paint()
              ..colorFilter = ColorFilter.mode(
                  HSLColor.fromAHSL(1, r.range(0, 360), 0.7, 0.5).toColor().withValues(alpha: 0.45),
                  BlendMode.color));
      }
    }
  });
}

/// A clear logo: transparent wordmark, gradient-filled with a keyline.
Future<ui.Image> logoWordmark(String text,
    {List<Color> fill = const [Color(0xFFFFF0C2), Color(0xFFE2A23B)],
    Color stroke = const Color(0xFF2A1408),
    int w = 900,
    int h = 260}) =>
    _render(w, h, (c, s) {
      // One line, as large as fits.
      final probe = (ui.ParagraphBuilder(ui.ParagraphStyle())
            ..pushStyle(ui.TextStyle(fontFamily: 'Anton', fontSize: 100, letterSpacing: 6))
            ..addText(text))
          .build()
        ..layout(const ui.ParagraphConstraints(width: 100000));
      final size = math.min(s.height * 0.62, 100 * (s.width - 60) / probe.maxIntrinsicWidth);
      ui.Paragraph build(Paint fg) {
        final b = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 1))
          ..pushStyle(ui.TextStyle(fontFamily: 'Anton', fontSize: size, letterSpacing: 6, foreground: fg))
          ..addText(text);
        return b.build()..layout(ui.ParagraphConstraints(width: s.width));
      }

      final strokeP = build(Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeJoin = StrokeJoin.round
        ..color = stroke);
      final top = (s.height - strokeP.height) / 2;
      c.drawParagraph(strokeP, Offset(0, top));
      final fillP = build(Paint()
        ..shader = ui.Gradient.linear(Offset(0, top + strokeP.height * 0.3),
            Offset(0, top + strokeP.height * 0.8), fill));
      c.drawParagraph(fillP, Offset(0, top));
    });

/// A TVDB-style 758×140 graphical banner: photo strip with the logo.
Future<ui.Image> bannerFrom(ui.Image photo, ui.Image logo) => _render(758, 140, (c, s) {
      final scale = s.width / photo.width;
      final srcH = s.height / scale;
      c.drawImageRect(photo, Rect.fromLTWH(0, photo.height * 0.42 - srcH / 2, photo.width.toDouble(), srcH),
          Offset.zero & s, Paint()..filterQuality = FilterQuality.medium);
      c.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(s.width, 0),
                const [Color(0xDD000000), Color(0x00000000)], const [0.15, 0.7]));
      final lw = s.width * 0.48, lh = lw * logo.height / logo.width;
      c.drawImageRect(logo, Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
          Rect.fromLTWH(18, (s.height - lh) / 2, lw, lh), Paint()..filterQuality = FilterQuality.medium);
    });

/// Vignette used by the photographic stand-ins (lens fall-off).
class LabelPrintTestVignette {
  static void paint(Canvas c, Size s) {
    c.drawRect(
        Offset.zero & s,
        Paint()
          ..shader = ui.Gradient.radial(s.center(Offset.zero), s.longestSide * 0.75,
              const [Color(0x00000000), Color(0x00000000), Color(0x88000000)], const [0, 0.55, 1]));
  }
}

/// Tapes with photographic artwork: everything present, and the fallbacks.
class PhotoTapes {
  PhotoTapes._();

  static Future<Map<String, TapeLabelData>> all() async {
    final bg = await photoBackground();
    final poster = await photoPoster();
    final logo = await logoWordmark('SLNKO V SIETI');
    final banner = await bannerFrom(bg, logo);
    final bg2 = await photoBackground(seed: 5);
    final darkLogo = await logoWordmark('MAJSTER KAT',
        fill: const [Color(0xFF1A1A22), Color(0xFF2B2B36)], stroke: const Color(0xFF0B0B10));
    final banner2 = await bannerFrom(bg2, darkLogo);
    final collage = await posterCollage();
    const synopsis =
        'Leto pred maturitou. Fajolo a Bela pozorujú zatmenie Slnka cez '
        'začadené sklíčko, kým sa ich svet pomaly rozpadá. Poetický obraz '
        'dospievania na brehu Dunaja, ktorý zmenil slovenský film.';
    return {
      // Everything TVDB can give: poster, logo, banner, background.
      'full_art': TapeLabelData(
        titleId: 'movie-slnko-1',
        title: 'Slnko v sieti',
        year: '1962',
        isMovie: true,
        poster: poster,
        logo: logo,
        banner: banner,
        background: bg,
        synopsis: synopsis,
        genres: const ['Dráma'],
        network: 'Koliba',
        runtime: '1h 33m',
        state: const TapeState(kind: TapeStateKind.watching, progress: 0.58),
      ),
      // No poster: the front is built from the background + the (dark)
      // logo, which needs the one-colour treatment on dark grounds.
      'no_poster': TapeLabelData(
        titleId: 'series-majster-kat-3',
        title: 'Majster kat',
        year: '1966',
        logo: darkLogo,
        banner: banner2,
        background: bg2,
        synopsis: 'Kat Eliáš má popraviť muža, ktorého nikto neviní. '
            'Mesto mlčí, rada mešťanov sa bojí a kat čaká na rozsudok, '
            'ktorý príde až s úsvitom.',
        genres: const ['Historický', 'Dráma'],
        network: 'STV',
        runtime: '52 min',
        state: const TapeState(kind: TapeStateKind.completed, progress: 1, watched: 6, total: 6),
      ),
      // Busy collage poster + logo: the logo is overlaid on the front.
      'busy_poster': TapeLabelData(
        titleId: 'series-kolaz-7',
        title: 'Ľudia z kolážovej ulice',
        year: '1991',
        poster: collage,
        logo: await logoWordmark('KOLÁŽ',
            fill: const [Color(0xFFFFFFFF), Color(0xFFE6F0FF)], stroke: const Color(0xFF0A1630)),
        genres: const ['Komédia'],
        state: const TapeState(kind: TapeStateKind.newEpisode, progress: 0.9, watched: 18, total: 20, nextCode: 'S02 E09'),
      ),
      // Only a banner: cassette spine prints it; everything else falls back.
      'banner_only': TapeLabelData(
        titleId: 'series-banner-2',
        title: 'Spadla z oblakov',
        year: '1978',
        banner: await bannerFrom(await photoBackground(seed: 12),
            await logoWordmark('SPADLA Z OBLAKOV',
                fill: const [Color(0xFFFFFFFF), Color(0xFFBFE3FF)],
                stroke: const Color(0xFF0B2A4A))),
        state: const TapeState.notStarted(total: 7),
      ),
    };
  }
}

/// The real-title sample shelf used by goldens and samples.
class SampleTapes {
  SampleTapes._();

  static Future<List<TapeLabelData>> all() async {
    final space = await posterSpace();
    final ring = await posterRing();
    final rose = await posterRose();
    final snow = await posterSnow();
    final forest = await posterForest();
    final tower = await posterTower();
    final logo = await logoDark();
    return [
      TapeLabelData(
        titleId: 'series-ordinacia-10',
        title: 'Ordinácia v ružovej záhrade',
        year: '2007',
        poster: rose,
        synopsis:
            'Lekári, sestry a pacienti jednej bratislavskej nemocnice. Láska, '
            'žiarlivosť a ťažké rozhodnutia medzi službami na pohotovosti a '
            'chodbami ružovej záhrady, kde sa ľudské osudy menia každý deň.',
        genres: const ['Dráma', 'Medicína'],
        network: 'Markíza',
        runtime: '50 min',
        state: const TapeState(
          kind: TapeStateKind.watching,
          progress: 0.42,
          watched: 214,
          total: 512,
          nextCode: 'S08 E14',
        ),
      ),
      TapeLabelData(
        titleId: 'movie-hviezdne-2',
        title: 'Hviezdne vojny: Epizóda V – Impérium vracia úder',
        year: '1980',
        isMovie: true,
        poster: space,
        synopsis:
            'Po zničení Hviezdy smrti sa povstalci ukrývajú na ľadovej planéte '
            'Hoth. Luke Skywalker hľadá majstra Yodu, zatiaľ čo Darth Vader '
            'neúnavne prenasleduje jeho priateľov naprieč galaxiou.',
        genres: const ['Sci-fi', 'Dobrodružný'],
        network: 'Lucasfilm',
        runtime: '2h 4m',
        state: const TapeState.completed(),
      ),
      TapeLabelData(
        titleId: 'movie-pan-6',
        title: 'Pán prsteňov: Spoločenstvo prsteňa',
        year: '2001',
        isMovie: true,
        poster: ring,
        synopsis:
            'Mladý hobit Frodo zdedí prsteň, ktorý ukrýva moc temného pána '
            'Saurona. S deviatimi spoločníkmi sa vydáva na nebezpečnú cestu '
            'do Mordoru, aby ho zničil v ohni Hory osudu.',
        genres: const ['Fantasy', 'Dobrodružný'],
        network: 'New Line',
        runtime: '2h 58m',
        state: const TapeState.notStarted(),
      ),
      const TapeLabelData(
        titleId: 'movie-vesnicko-1',
        title: 'Vesničko má středisková',
        year: '1985',
        isMovie: true,
        synopsis:
            'Řidič Pávek už nemůže vydržet se svým pomalým spolujezdcem Otíkem '
            'a chce ho poslat do Prahy. Celá vesnice se ale postaví za něj — '
            'laskavá komedie o sousedství, které drží pohromadě.',
        genres: ['Komedie', 'Drama'],
        network: 'Barrandov',
        runtime: '1h 38m',
        state: TapeState.completed(),
      ),
      TapeLabelData(
        titleId: 'movie-popelka-1',
        title: 'Tři oříšky pro Popelku',
        year: '1973',
        isMovie: true,
        poster: snow,
        synopsis:
            'Popelka dostane tři kouzelné oříšky a s nimi šanci vymanit se z '
            'nadvlády macechy. Zimní pohádka o odvaze, lásce a princi, který '
            'musí uhodnout hádanku.',
        genres: const ['Pohádka', 'Romantický'],
        network: 'DEFA',
        runtime: '1h 25m',
        state: const TapeState(kind: TapeStateKind.watching, progress: 0.47),
      ),
      TapeLabelData(
        titleId: 'series-dark-4',
        title: 'Dark',
        year: '2017',
        poster: forest,
        logo: logo,
        synopsis:
            'A missing child sets four families on a frantic hunt for answers '
            'as they unearth a mind-bending mystery that spans three '
            'generations of the small German town of Winden.',
        genres: const ['Mystery', 'Sci-Fi', 'Thriller'],
        network: 'Netflix',
        runtime: '55 min',
        state: const TapeState(
          kind: TapeStateKind.newEpisode,
          progress: 0.96,
          watched: 25,
          total: 26,
          nextCode: 'S03 E08',
        ),
      ),
      const TapeLabelData(
        titleId: 'series-lost-2',
        title: 'Lost',
        year: '2004',
        synopsis:
            'Survivors of a plane crash are forced to work together in order '
            'to stay alive on a seemingly deserted tropical island.',
        genres: ['Drama', 'Mystery', 'Adventure'],
        network: 'ABC',
        runtime: '43 min',
        state: TapeState(
          kind: TapeStateKind.watching,
          progress: 0.31,
          watched: 37,
          total: 121,
          nextCode: 'S02 E14',
        ),
      ),
      TapeLabelData(
        titleId: 'series-chernobyl-0',
        title: 'Chernobyl',
        year: '2019',
        poster: tower,
        synopsis:
            'The true story of one of the worst man-made catastrophes in '
            'history and of the brave men and women who sacrificed to save '
            'Europe from unimaginable disaster.',
        genres: const ['Drama', 'History'],
        network: 'HBO',
        runtime: '65 min',
        state: const TapeState(
          kind: TapeStateKind.watching,
          progress: 0.6,
          watched: 3,
          total: 5,
          nextCode: 'S01 E04',
        ),
      ),
    ];
  }
}

/// PNG bytes of [img].
Future<Uint8List> pngBytes(ui.Image img) async {
  final b = await img.toByteData(format: ui.ImageByteFormat.png);
  return b!.buffer.asUint8List();
}
