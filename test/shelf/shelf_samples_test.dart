// Writes composed shelf rows and inspect-view pictures to
// build/shelf_samples/ for visual inspection — with the fixture art and
// with the real label composer. Passes unless composing throws.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/shelf/inspect/hero_frames.dart';
import 'package:showtrack/shelf/labels/label_composer.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';
import 'package:showtrack/shelf/shelf_layout.dart';
import 'package:showtrack/shelf/shelf_renderer.dart';

import 'shelf_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final out = Directory('build/shelf_samples');
  final ids = [for (var i = 0; i < 21; i++) 'series-sample-$i'];
  final states = <String, TapeState>{
    ids[3]: const TapeState(
        kind: TapeStateKind.watching,
        progress: 0.4,
        watched: 4,
        total: 10,
        nextCode: 'S01 E05'),
    ids[8]: const TapeState.notStarted(),
    ids[13]: const TapeState.notStarted(),
    ids[5]: const TapeState(
        kind: TapeStateKind.newEpisode,
        progress: 0.9,
        watched: 9,
        total: 10,
        nextCode: 'S02 E10'),
  };
  FixtureTapeSource source() => FixtureTapeSource({
        for (var i = 0; i < ids.length; i++)
          ids[i]: sampleTitles[i % sampleTitles.length],
      }, states: states);

  Future<void> writeShelf(ShelfRenderer r, String name) async {
    await r.ready;
    final bays = r.layout!.layout([
      ShelfSection(label: 'DRAMA', tapes: [
        for (var i = 0; i < 12; i++)
          ShelfTape(
              ids[i],
              i == 3 || i == 5
                  ? TapePose.pulled
                  : (i == 8 ? TapePose.sealed : TapePose.upright)),
      ]),
      ShelfSection(label: 'SCI-FI', tapes: [
        for (var i = 12; i < 21; i++)
          ShelfTape(ids[i], i == 13 ? TapePose.sealed : TapePose.upright),
      ]),
    ]);
    out.createSync(recursive: true);
    final sheet = RowSheet();
    for (final b in bays) {
      sheet.add(await r.composeRow(b, 1116));
    }
    await File('${out.path}/$name.png')
        .writeAsBytes(await pngOf(await sheet.render()));
  }

  test('shelf sample, fixture art', () async {
    await loadShelfFonts();
    final r = ShelfRenderer(source: source(), spinePainter: fixtureSpineArt);
    await writeShelf(r, 'shelf_fixture');
    r.dispose();
  });

  test('shelf sample, label composer', () async {
    await loadShelfFonts();
    final r = ShelfRenderer(source: source());
    await writeShelf(r, 'shelf_labels');
    r.dispose();
  });

  test('hero sample, label composer', () async {
    await loadShelfFonts();
    final r = ShelfRenderer(source: source());
    await r.ready;
    final m = r.manifest!;
    final g = m.hero;
    final hero = HeroFrames(manifest: m, compositor: r.compositor!)
      ..displayHeightPx = 450
      ..cassetteWidthPx = 450;
    final snap = (await r.source.labelData(ids[3]))!;
    hero.setAtlas(await LabelComposer().composeHero(snap.data, sizePx: 1536));
    final wanted = [0, g.front ~/ 2, g.front, g.front * 2, g.front * 3];
    hero
      ..want(wanted)
      ..wantFront()
      ..wantCassette(0.4);
    while (!hero.isIdle) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Contact sheet on a light floor: the rotation frames, then the cassette.
    final fw = hero.frame(0)!.width, fh = hero.frame(0)!.height;
    final rec = PictureRecorder();
    final c = Canvas(rec);
    final w = fw * wanted.length, h = fh + hero.cassette!.height;
    c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..color = const Color(0xFFEDEDF0));
    for (var i = 0; i < wanted.length; i++) {
      c.drawImage(hero.frame(g.nearestAvailable(wanted[i]))!,
          Offset(i * fw.toDouble(), 0), Paint());
    }
    c.drawImage(hero.cassette!, Offset(0, fh.toDouble()), Paint());
    final sheet = await rec.endRecording().toImage(w, h);
    out.createSync(recursive: true);
    await File('${out.path}/hero_frames.png').writeAsBytes(await pngOf(sheet));
    await File('${out.path}/hero_front.png')
        .writeAsBytes(await pngOf(hero.front!));
    snap.dispose();
    hero.dispose();
    r.dispose();
  });
}

/// Stacks composed rows (base + rail) into one image, like composite.py.
class RowSheet {
  final List<ShelfRowImage> rows = [];
  void add(ShelfRowImage r) => rows.add(r);

  Future<Image> render() async {
    final w = rows.first.base.width;
    final h = rows.fold<int>(0, (s, r) => s + r.base.height);
    final scale = w / 1116;
    final rec = PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..color = const Color(0xFF050506));
    var y = 0.0;
    for (final r in rows) {
      c.drawImage(r.base, Offset(0, y), Paint());
      c.drawImage(r.rail,
          Offset(r.railRect.left * scale, y + r.railRect.top * scale), Paint());
      y += r.base.height;
    }
    return rec.endRecording().toImage(w, h);
  }
}
