// Writes composed atlases to build/label_samples/ for visual inspection
// and for the Blender showcase renders. Always passes (it only fails if
// composing itself throws).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/shelf/labels/atlas_layout.dart';
import 'package:showtrack/shelf/labels/label_composer.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';

import 'label_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('write label samples to build/label_samples', () async {
    await loadLabelFonts();
    final tapes = await SampleTapes.all();
    final composer = LabelComposer();
    final out = Directory('build/label_samples')..createSync(recursive: true);

    // Five titles covering all four states: watching (poster), completed
    // (poster), not started (poster), completed without a poster, new episode
    // (poster + clear logo).
    final picks = {
      'ordinacia': tapes[0],
      'hviezdne_vojny': tapes[1],
      'pan_prstenov': tapes[2],
      'vesnicko': tapes[3],
      'dark': tapes[5],
    };
    for (final e in picks.entries) {
      final hero = await composer.composeHero(e.value, sizePx: 1536);
      await File('${out.path}/hero_1536_${e.key}.png').writeAsBytes(await pngBytes(hero));
      final shelf = await composer.composeShelf(e.value, widthPx: 224);
      await File('${out.path}/shelf_224_${e.key}.png').writeAsBytes(await pngBytes(shelf));
      hero.dispose();
      shelf.dispose();
    }

    // Photographic artwork (poster / logo / banner / background) and the
    // fallbacks when some of it is missing.
    final photos = await PhotoTapes.all();
    for (final e in photos.entries) {
      final hero = await composer.composeHero(e.value, sizePx: 1536);
      await File('${out.path}/hero_1536_photo_${e.key}.png').writeAsBytes(await pngBytes(hero));
      final shelf = await composer.composeShelf(e.value, widthPx: 224);
      await File('${out.path}/shelf_224_photo_${e.key}.png').writeAsBytes(await pngBytes(shelf));
      hero.dispose();
      shelf.dispose();
    }

    // A contact sheet of all sample spines (plus their front strips).
    final images = <ui.Image>[];
    for (final t in tapes) {
      images.add(await composer.composeShelf(t, widthPx: 224));
    }
    final sheet = await _sheet(images);
    await File('${out.path}/shelf_row_224.png').writeAsBytes(await pngBytes(sheet));
    // A wall of 30 different titles: does the shelf look collected?
    final posters = [
      await posterSpace(), await posterRing(), await posterRose(),
      await posterSnow(), await posterForest(), await posterTower(),
    ];
    const wallTitles = [
      'Pelíšky', 'Kolja', 'Obecná škola', 'Slnko v sieti', 'Marečku, podejte mi pero!',
      'Jára Cimrman ležící, spící', 'Návštěvníci', 'Arabela', 'Pan Tau', 'Spadla z oblakov',
      'Majster kat', 'Perinbaba', 'Fargo', 'Twin Peaks', 'Mad Men', 'The Wire',
      'Breaking Bad', 'Severance', 'Stranger Things', 'Sherlock', 'The Office',
      'Ľalie poľné', 'Štúrovci', 'Dobrodružství kriminalistiky', 'Želary',
      'Až přijde kocour', 'Kameňák', 'Rebelové', 'Fontána pre Zuzanu', 'Utrpení mladého Boháčka',
    ];
    const states = [
      TapeState.notStarted(total: 10),
      TapeState(kind: TapeStateKind.watching, progress: 0.4, watched: 4, total: 10),
      TapeState.completed(total: 10),
      TapeState(kind: TapeStateKind.newEpisode, progress: 0.9, watched: 9, total: 10, nextCode: 'S02 E01'),
    ];
    final wall = <ui.Image>[];
    for (var i = 0; i < wallTitles.length; i++) {
      final d = TapeLabelData(
        titleId: '${i.isEven ? 'series' : 'movie'}-${70000 + i * 1237}',
        title: wallTitles[i],
        year: '${1965 + (i * 7) % 58}',
        isMovie: i.isOdd,
        poster: i % 3 == 2 ? null : posters[(i * 5) % posters.length],
        state: states[(i * 3) % states.length],
      );
      wall.add(await composer.composeShelf(d, widthPx: 224));
    }
    final wallImg = await _wall(wall, 15);
    await File('${out.path}/shelf_wall_30.png').writeAsBytes(await pngBytes(wallImg));
    debugPrint('label samples written to ${out.absolute.path}');
  });
}

Future<ui.Image> _sheet(List<ui.Image> atlases) async {
  final layout = AtlasManifest.standard.spine;
  final a0 = atlases.first;
  final size = Size(a0.width.toDouble(), a0.height.toDouble());
  const gap = 10.0;
  final w = (size.width + gap) * atlases.length + gap;
  final h = size.height + 2 * gap;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF1A1A1C));
  final spine = layout.pixelRect('spine', size);
  final strip = layout.pixelRect('front_strip', size);
  for (var i = 0; i < atlases.length; i++) {
    final x = gap + i * (size.width + gap);
    c.drawImageRect(atlases[i], spine, Rect.fromLTWH(x, gap, spine.width, spine.height), Paint());
    c.drawImageRect(atlases[i], strip,
        Rect.fromLTWH(x + spine.width, gap, strip.width, strip.height), Paint());
  }
  final pic = rec.endRecording();
  return pic.toImage(w.round(), h.round());
}

/// Spines only, [perRow] to a row.
Future<ui.Image> _wall(List<ui.Image> atlases, int perRow) async {
  final layout = AtlasManifest.standard.spine;
  final a0 = atlases.first;
  final spine = layout.pixelRect('spine', Size(a0.width.toDouble(), a0.height.toDouble()));
  const gap = 4.0, pad = 14.0;
  final rows = (atlases.length / perRow).ceil();
  final w = pad * 2 + perRow * spine.width + (perRow - 1) * gap;
  final h = pad * 2 + rows * spine.height + (rows - 1) * pad;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF141416));
  for (var i = 0; i < atlases.length; i++) {
    final x = pad + (i % perRow) * (spine.width + gap);
    final y = pad + (i ~/ perRow) * (spine.height + pad);
    c.drawImageRect(atlases[i], spine, Rect.fromLTWH(x, y, spine.width, spine.height), Paint());
  }
  return rec.endRecording().toImage(w.round(), h.round());
}