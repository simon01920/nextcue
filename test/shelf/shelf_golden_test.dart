// Goldens for the tape widget and the shelf widget. They render through
// the real plate shader (plate.frag runs under flutter test) with the
// fixture spine art from shelf_test_support.dart, so they pin the
// compositor, the layout and the widgets — not the label composer's look.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';
import 'package:showtrack/shelf/shelf_layout.dart';
import 'package:showtrack/shelf/shelf_renderer.dart';
import 'package:showtrack/shelf/shelf_view.dart';
import 'package:showtrack/shelf/tape_view.dart';

import 'shelf_test_support.dart';

/// Lets real async work (decoding, toImage) finish, pumping between steps
/// so continuations queued in the test zone run.
Future<void> settle(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump();
  }
}

void main() {
  final ids = [for (var i = 0; i < 21; i++) 'series-golden-$i'];
  final source = FixtureTapeSource({
    for (var i = 0; i < ids.length; i++)
      ids[i]: sampleTitles[i % sampleTitles.length],
  }, states: {
    ids[3]: const TapeState(kind: TapeStateKind.watching, progress: 0.5),
  });
  final sections = [
    ShelfSection(label: 'WATCHING', tapes: [
      for (var i = 0; i < 12; i++)
        ShelfTape(
            ids[i],
            i == 3
                ? TapePose.pulled
                : (i == 8 ? TapePose.sealed : TapePose.upright)),
    ]),
    ShelfSection(label: 'COMPLETED', tapes: [
      for (var i = 12; i < 17; i++) ShelfTape(ids[i]),
    ]),
  ];

  late ShelfRenderer renderer;

  Widget host(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0B0C),
          body: ShelfScope(renderer: renderer, child: child),
        ),
      );

  setUp(() {
    renderer = ShelfRenderer(source: source, spinePainter: fixtureSpineArt);
  });

  tearDown(() => renderer.dispose());

  testWidgets('golden: shelf widget (two bays)', (tester) async {
    tester.view.physicalSize = const Size(558, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await loadShelfFonts();
      await renderer.ready;
      // Compose what the widget will ask for, so the golden shows the
      // finished rows rather than the loading shimmer.
      final w = renderer.rowWidthPx(558, 1);
      for (final bay in renderer.layout!.layout(sections)) {
        await renderer.composeRow(bay, w);
      }
    });
    await tester.pumpWidget(host(Align(
      alignment: Alignment.topCenter,
      child: ShelfColumn(sections: sections),
    )));
    await settle(tester, rounds: 3);
    expect(renderer.isIdle, isTrue);
    expect(find.byType(ShelfBayView), findsNWidgets(2));
    await expectLater(find.byType(ShelfColumn),
        matchesGoldenFile('goldens/shelf_widget.png'));
  });

  testWidgets('golden: tape widget (upright, sealed, pulled)', (tester) async {
    tester.view.physicalSize = const Size(3 * 86 + 40, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await loadShelfFonts();
      await renderer.ready;
    });
    await tester.pumpWidget(host(Align(
      alignment: Alignment.topCenter,
      child: Row(
        key: const Key('tapes'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, pose) in [
            (1, TapePose.upright),
            (8, TapePose.sealed),
            (3, TapePose.pulled),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                  width: 86, child: TapeView(titleId: ids[i], pose: pose)),
            ),
        ],
      ),
    )));
    await settle(tester);
    await expectLater(
        find.byKey(const Key('tapes')), matchesGoldenFile('goldens/tape_widget.png'));
  });

  testWidgets('a tape is a button with its title for screen readers',
      (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(558, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => renderer.ready);
    await tester.pumpWidget(host(ShelfColumn(sections: sections)));
    await tester.pump();
    expect(
      find.bySemanticsLabel(sampleTitles[0]),
      findsOneWidget,
    );
    final node = tester.getSemantics(find.bySemanticsLabel(sampleTitles[0]));
    expect(node.hint, 'Double tap to inspect');
    expect(find.bySemanticsLabel('WATCHING · 12'), findsOneWidget);
    handle.dispose();
  });
}
