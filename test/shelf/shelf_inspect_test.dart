import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:showtrack/data/mock_repository.dart';
import 'package:showtrack/data/repository.dart';
import 'package:showtrack/router.dart';
import 'package:showtrack/screens/collection_screen.dart';
import 'package:showtrack/screens/profile_screen.dart';
import 'package:showtrack/services/auth_service.dart';
import 'package:showtrack/shelf/inspect/progress_panel.dart';
import 'package:showtrack/shelf/shelf_layout.dart';
import 'package:showtrack/shelf/shelf_renderer.dart';
import 'package:showtrack/shelf/shelf_view.dart';
import 'package:showtrack/shelf/tape_catalog.dart';
import 'package:showtrack/state/app_state.dart';
import 'package:showtrack/theme/app_theme.dart';
import 'package:showtrack/widgets/vhs_shelf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shelf_test_support.dart';

/// Real async work (decoding, toImage) between fake-time frames.
Future<void> settle(WidgetTester tester,
    {int rounds = 40, Duration frame = const Duration(milliseconds: 16)}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(frame);
  }
}

void main() {
  late AppState appState;
  late ShelfRenderer renderer;
  const repo = MockRepository();

  Widget host(Widget child,
          {bool reduceMotion = false, bool light = false, double textScale = 1}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          Provider<ContentRepository>.value(value: repo),
        ],
        child: MaterialApp(
          theme: light ? AppTheme.light : AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: reduceMotion,
                textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: ShelfScope(renderer: renderer, child: child),
          ),
        ),
      );

  setUp(() {
    appState = AppState();
    renderer = ShelfRenderer(
      source: TapeCatalog(repo: repo, appState: appState),
      spinePainter: fixtureSpineArt,
      heroPainter: fixtureHeroArt,
    );
  });

  tearDown(() => renderer.dispose());

  Future<void> pumpShelf(WidgetTester tester, List<String> ids,
      {bool reduceMotion = false,
      bool light = false,
      double textScale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await loadShelfFonts();
      await renderer.ready;
    });
    await tester.pumpWidget(host(
      ListView(children: [VhsShelf(ids: ids)]),
      reduceMotion: reduceMotion,
      light: light,
      textScale: textScale,
    ));
    await settle(tester, rounds: 30, frame: const Duration(milliseconds: 100));
  }

  testWidgets('favourites shelf composes its bays from AppState',
      (tester) async {
    appState.setStatus('279830', TrackStatus.watching);
    appState.setWatched('279830:1:1', true);
    await pumpShelf(tester, ['279830', '3d9af89d']);
    expect(find.byType(ShelfBayView), findsOneWidget);
    expect(renderer.isIdle, isTrue);
    expect(renderer.rowCount, greaterThanOrEqualTo(1));
    // Labels came from the repository's titles.
    expect(find.bySemanticsLabel(RegExp('^Your Lie in April, show, watching')),
        findsOneWidget);
  });

  testWidgets(
      'inspect (reduced motion): jumps to the front, marks the next episode '
      'watched through AppState, and closes', (tester) async {
    appState.setStatus('279830', TrackStatus.watching);
    await pumpShelf(tester, ['279830'], reduceMotion: true);
    await tester.tap(find.bySemanticsLabel(RegExp('^Your Lie in April')));
    await settle(tester, rounds: 60, frame: const Duration(milliseconds: 50));
    expect(find.byType(ProgressPanel), findsOneWidget);
    // No lift in reduced motion: the tape stays on the shelf.
    expect(renderer.inspecting.value, isNull);
    final mark = find.text('Mark S01 E01 watched');
    expect(mark, findsOneWidget);
    await tester.tap(mark);
    await tester.pump();
    expect(appState.isWatched('279830:1:1'), isTrue);
    expect(find.text('UNDO'), findsOneWidget);
    await tester.tap(find.text('UNDO'));
    await tester.pump();
    expect(appState.isWatched('279830:1:1'), isFalse);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester, rounds: 10, frame: const Duration(milliseconds: 100));
    expect(find.byType(ProgressPanel), findsNothing);
    await tester.pump(const Duration(seconds: 6)); // let timers lapse
  });

  testWidgets('inspect at 200 % text in light mode lays out without overflow',
      (tester) async {
    appState.setStatus('279830', TrackStatus.watching);
    appState.setWatched('279830:1:1', true);
    await pumpShelf(tester, ['279830'],
        reduceMotion: true, light: true, textScale: 2);
    await tester.tap(find.bySemanticsLabel(RegExp('^Your Lie in April')));
    await settle(tester, rounds: 40, frame: const Duration(milliseconds: 50));
    expect(find.byType(ProgressPanel), findsOneWidget);
    expect(find.text('Mark S01 E02 watched'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester, rounds: 10, frame: const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('inspect (motion): the tape lifts out, turns, drags, closes',
      (tester) async {
    appState.setStatus('279830', TrackStatus.watching);
    await pumpShelf(tester, ['279830', '3d9af89d'], light: true);
    await tester.tap(find.bySemanticsLabel(RegExp('^Your Lie in April')));
    await settle(tester, rounds: 8);
    // Lifted out: hidden on the shelf while inspected.
    expect(renderer.inspecting.value, '279830');
    await settle(tester, rounds: 80, frame: const Duration(milliseconds: 32));
    expect(find.byType(ProgressPanel), findsOneWidget);
    final stage = find.bySemanticsLabel(RegExp('Drag sideways'));
    expect(stage, findsOneWidget);
    await tester.drag(stage, const Offset(-160, 0));
    await settle(tester, rounds: 30, frame: const Duration(milliseconds: 32));
    await tester.tap(find.byTooltip('Close'));
    await settle(tester, rounds: 10, frame: const Duration(milliseconds: 100));
    expect(find.byType(ProgressPanel), findsNothing);
    expect(renderer.inspecting.value, isNull);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('collection groups every tracked title into sections',
      (tester) async {
    for (var i = 0; i < 30; i++) {
      appState.setStatus('series-c$i', switch (i % 3) {
        0 => TrackStatus.completed,
        1 => TrackStatus.planToWatch,
        _ => TrackStatus.watching,
      });
    }
    appState.setWatched('series-c2:1:1', true);
    final sections = CollectionScreen.sectionsFor(appState);
    expect(sections.map((s) => s.label),
        ['WATCHING', 'NOT STARTED', 'COMPLETED']);
    expect(sections.map((s) => s.tapes.length), [10, 10, 10]);
    // Most recently watched first.
    expect(sections.first.tapes.first.titleId, 'series-c2');
    expect(sections.first.tapes.first.pose, TapePose.pulled);
    expect(sections[1].tapes.every((t) => t.pose == TapePose.sealed), isTrue);
    expect(sections[2].tapes.every((t) => t.pose == TapePose.upright), isTrue);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => renderer.ready);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        Provider<ContentRepository>.value(value: repo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: ShelfScope(renderer: renderer, child: const CollectionScreen()),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('30 tapes'), findsOneWidget);
    // Lazy: only the bays near the viewport exist.
    final built = find.byType(ShelfBayView).evaluate().length;
    expect(built, inInclusiveRange(1, 3));
    await tester.pump(const Duration(seconds: 6));
  });

  test('500 tracked titles lay out in one pass', () async {
    final s = AppState();
    for (var i = 0; i < 500; i++) {
      s.setStatus('series-x$i',
          i.isEven ? TrackStatus.completed : TrackStatus.planToWatch);
    }
    final watch = Stopwatch()..start();
    final sections = CollectionScreen.sectionsFor(s);
    final manifest = await renderer.ready.then((_) => renderer.layout!);
    final bays = manifest.layout(sections);
    watch.stop();
    expect(sections.fold<int>(0, (n, x) => n + x.tapes.length), 500);
    expect(bays.length, 2 * ((250 + 11) ~/ 12));
    expect(watch.elapsedMilliseconds, lessThan(250));
  });

  testWidgets('without a ShelfScope the shelf uses an app-wide renderer',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appState.setStatus('279830', TrackStatus.completed);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        Provider<ContentRepository>.value(value: repo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ListView(children: const [VhsShelf(ids: ['279830'])]),
        ),
      ),
    ));
    await settle(tester, rounds: 40, frame: const Duration(milliseconds: 100));
    expect(find.byType(ShelfBayView), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Your Lie in April, show, completed')),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('an empty favourites shelf shows the hint', (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        Provider<ContentRepository>.value(value: repo),
      ],
      child: const MaterialApp(home: Scaffold(body: VhsShelf(ids: []))),
    ));
    expect(find.textContaining('Tap the heart'), findsOneWidget);
    expect(find.byType(ShelfColumn), findsNothing);
  });

  testWidgets('the profile links to the collection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(path: '/profile', builder: (c, s) => const Scaffold(body: ProfileScreen())),
      GoRoute(path: '/collection', builder: (c, s) => const CollectionScreen()),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider(create: (_) => AuthController(LocalAuthService())),
        Provider<ContentRepository>.value(value: repo),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('profileCollectionLink')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collectionScreen')), findsOneWidget);
    expect(find.text('No tapes yet'), findsOneWidget);
  });

  test('the app router exposes /collection', () {
    final router = buildRouter(AuthController(LocalAuthService()));
    expect(
      [for (final r in router.configuration.routes) if (r is GoRoute) r.path],
      contains('/collection'),
    );
  });
}
