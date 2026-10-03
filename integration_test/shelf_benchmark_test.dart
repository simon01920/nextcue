// Frame-time benchmark for a 100-tape shelf (docs/AUDIT.md §6).
//
//   flutter drive --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/shelf_benchmark_test.dart -d <device>
//
// Results land in build/integration_response_data.json. Uses the real
// ShelfRenderer, label composer and plate shader over a fixed title list
// (no repository, no network), so it measures the shelf, not TVDB latency.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';
import 'package:showtrack/shelf/shelf_layout.dart';
import 'package:showtrack/shelf/shelf_renderer.dart';
import 'package:showtrack/shelf/shelf_view.dart';
import 'package:showtrack/shelf/tape_source.dart';

const _names = [
  'The Expanse', 'Dark', 'Hra o tróny', 'Severance', 'Fargo', 'Twin Peaks',
  'Chernobyl', 'Kto chce byť milionárom?', 'Slnko v sieti', 'Breaking Bad',
  'Mr. Robot', 'Arcane', 'Stranger Things', 'Andor', 'Shōgun',
  'Better Call Saul', 'Ted Lasso', 'Mindhunter', 'The Bear', 'Westworld',
  'Ordinácia v ružovej záhrade', 'Pán prsteňov: Prstene moci', 'Vesničko má středisková',
  'Succession', 'Fleabag',
];

class _BenchSource extends ChangeNotifier implements TapeSource {
  _BenchSource(this.count);

  final int count;

  String _title(String id) {
    final i = int.parse(id.split('-').last);
    final base = _names[i % _names.length];
    return i < _names.length ? base : '$base ${i ~/ _names.length + 1}';
  }

  TapeState _state(String id) {
    final i = int.parse(id.split('-').last);
    if (i < 10) {
      return TapeState(kind: TapeStateKind.watching, progress: (i + 1) / 12,
          watched: i + 1, total: 12, nextCode: 'S01 E${(i + 2).toString().padLeft(2, '0')}');
    }
    if (i < 40) return const TapeState(kind: TapeStateKind.notStarted, total: 10);
    if (i % 9 == 0) return const TapeState(kind: TapeStateKind.newEpisode, total: 20, watched: 19, progress: 0.95);
    return const TapeState(kind: TapeStateKind.completed, total: 10, watched: 10);
  }

  @override
  String labelKey(String titleId, {LabelUse use = LabelUse.shelf}) =>
      'bench|$titleId|${_state(titleId).cacheKey}';

  @override
  Future<LabelSnapshot?> labelData(String titleId,
          {LabelUse use = LabelUse.shelf, Duration? patience}) async =>
      LabelSnapshot(
          TapeLabelData(
              titleId: titleId,
              title: _title(titleId),
              year: '${1985 + titleId.hashCode % 35}',
              state: _state(titleId)),
          labelKey(titleId));

  @override
  String semanticsLabel(String titleId) => _title(titleId);

  @override
  void prefetch(Iterable<String> titleIds) {}
}

List<ShelfSection> _sections(int count) {
  ShelfTape tape(int i) => ShelfTape('series-bench-$i',
      i < 10 ? TapePose.pulled : (i < 40 ? TapePose.sealed : TapePose.upright));
  return [
    ShelfSection(label: 'WATCHING', tapes: [for (var i = 0; i < 10; i++) tape(i)]),
    ShelfSection(label: 'NOT STARTED', tapes: [for (var i = 10; i < 40; i++) tape(i)]),
    ShelfSection(label: 'COMPLETED', tapes: [for (var i = 40; i < count; i++) tape(i)]),
  ];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('100-tape shelf scrolls at frame rate', (tester) async {
    const count = 100;
    final source = _BenchSource(count);
    final renderer = ShelfRenderer(source: source);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ShelfScope(
        renderer: renderer,
        child: Scaffold(
          backgroundColor: const Color(0xFF0E0E10),
          body: CustomScrollView(
            key: const Key('benchShelf'),
            slivers: [SliverShelf(sections: _sections(count))],
          ),
        ),
      ),
    ));
    await Future<void>.delayed(const Duration(seconds: 3));
    final list = find.byKey(const Key('benchShelf'));

    Future<void> sweep() async {
      for (var i = 0; i < 6; i++) {
        await tester.fling(list, const Offset(0, -900), 1800);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      for (var i = 0; i < 6; i++) {
        await tester.fling(list, const Offset(0, 900), 1800);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }

    // First pass: rows compose (labels + offscreen shader draws) as they
    // scroll into view.
    await binding.watchPerformance(sweep, reportKey: 'shelf_scroll_cold');
    // Second pass: the same scrolling over cached rows (as far as the row
    // cache holds them).
    await binding.watchPerformance(sweep, reportKey: 'shelf_scroll_warm');
  });

  // Control: the same scroll over a plain list of bay-sized images (no
  // shelf code at all), to separate the device's own blit cost from ours.
  testWidgets('control: plain list of bay-sized images', (tester) async {
    final data = await rootBundle.load('assets/plates/shelf/bay_0_color.webp');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final image = (await codec.getNextFrame()).image;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0E0E10),
        body: CustomScrollView(
          key: const Key('control'),
          slivers: [
            SliverList.builder(
              itemCount: 12,
              itemBuilder: (_, i) => AspectRatio(
                aspectRatio: 1116 / 690,
                child: RawImage(image: image, fit: BoxFit.fill),
              ),
            ),
          ],
        ),
      ),
    ));
    await Future<void>.delayed(const Duration(seconds: 2));
    final list = find.byKey(const Key('control'));
    await binding.watchPerformance(() async {
      for (var i = 0; i < 6; i++) {
        await tester.fling(list, const Offset(0, -900), 1800);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      for (var i = 0; i < 6; i++) {
        await tester.fling(list, const Offset(0, 900), 1800);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }, reportKey: 'control_image_list');
  });
}
