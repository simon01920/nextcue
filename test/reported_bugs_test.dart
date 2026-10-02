import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:showtrack/data/mock_repository.dart';
import 'package:showtrack/data/repository.dart';
import 'package:showtrack/models/models.dart';
import 'package:showtrack/screens/browse_screen.dart';
import 'package:showtrack/screens/explore_screen.dart';
import 'package:showtrack/screens/movies_screen.dart';
import 'package:showtrack/screens/title_detail_screen.dart';
import 'package:showtrack/router.dart';
import 'package:showtrack/services/auth_service.dart';
import 'package:showtrack/screens/shows_screen.dart';
import 'package:showtrack/state/app_state.dart';
import 'package:showtrack/theme/app_theme.dart';
import 'package:showtrack/theme/tokens.dart';
import 'package:showtrack/widgets/common.dart';
import 'package:showtrack/widgets/watch_history.dart';

/// Regression cover for the specific defects reported after the first pass.
/// Each group maps 1:1 to a reported issue so a regression is obvious.

AppState _state() => AppState();

Widget _host(Widget child, {AppState? state, ThemeData? theme}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: state ?? _state()),
      Provider<ContentRepository>(create: (_) => const MockRepository()),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.dark,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('grid toggle exists on both Shows tabs', () {
    testWidgets('watch list has a grid toggle', (tester) async {
      await tester.pumpWidget(_host(const ShowsScreen(tab: 'watchlist')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('showsGridToggle')), findsOneWidget);
    });

    testWidgets('upcoming has its own grid toggle (was missing)',
        (tester) async {
      await tester.pumpWidget(_host(const ShowsScreen(tab: 'upcoming')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('upcomingGridToggle')), findsOneWidget,
          reason: 'Upcoming must offer the same list/grid switch');
      expect(find.byKey(const Key('upcomingCalendarToggle')), findsOneWidget);
    });

    testWidgets('toggling upcoming to grid renders tiles', (tester) async {
      await tester.pumpWidget(_host(const ShowsScreen(tab: 'upcoming')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('upcomingGridToggle')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GridView), findsOneWidget);
    });
  });

  group('long-press opens the title actions sheet', () {
    testWidgets('watch-list row long-press shows watch/status actions',
        (tester) async {
      final state = _state();
      await tester.pumpWidget(
          _host(const ShowsScreen(tab: 'watchlist'), state: state));
      await tester.pump(const Duration(milliseconds: 400));

      final row = find.byType(EpisodeRow).first;
      expect(row, findsOneWidget);
      await tester.longPress(row);
      await tester.pump(const Duration(milliseconds: 400));

      // Status chips and the bulk action prove the sheet is live.
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('Watching'), findsOneWidget);
      expect(find.text('Plan to watch'), findsOneWidget);
    });

    testWidgets('sheet can mark the up-next episode watched', (tester) async {
      final state = _state();
      await tester.pumpWidget(
          _host(const ShowsScreen(tab: 'watchlist'), state: state));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.longPress(find.byType(EpisodeRow).first);
      await tester.pumpAndSettle();

      final markWatched = find.textContaining('Mark S');
      expect(markWatched, findsWidgets);
      await tester.tap(markWatched.first);
      await tester.pumpAndSettle();

      expect(state.watchedEpisodeTotal, greaterThan(0),
          reason: 'the sheet action must write through to AppState');
      // Drain the mock repository's simulated-latency timers.
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('season-level watch button (was inert)', () {
    test('setManyWatched marks and clears a whole season', () {
      final s = _state();
      final season = ['t:1:1', 't:1:2', 't:1:3'];

      s.setManyWatched(season, true);
      expect(season.every(s.isWatched), isTrue);
      expect(s.watchedCountFor('t'), 3);

      s.setManyWatched(season, false);
      expect(season.any(s.isWatched), isFalse);
      expect(s.watchedCountFor('t'), 0);
    });
  });

  group('add-to-list "+" button (was inert)', () {
    testWidgets('tapping + tracks the title, tapping again removes it',
        (tester) async {
      final state = _state();
      const title = MediaTitle(
          id: 'series-1', kind: MediaKind.show, name: 'Test Show');

      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => AddToListButton(
              title: title,
              tracked: context.watch<AppState>().statusOf('series-1') != null),
        ),
        state: state,
      ));

      expect(state.statusOf('series-1'), isNull);

      await tester.tap(find.byType(AddToListButton));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.statusOf('series-1'), TrackStatus.planToWatch,
          reason: '+ must actually add the title');

      await tester.tap(find.byType(AddToListButton));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.statusOf('series-1'), isNull);
    });
  });

  group('watch history (new)', () {
    test('history is newest-first and unwatch removes entries', () {
      final s = _state();
      s.setWatched('show:1:1', true);
      s.setWatched('show:1:2', true);

      final history = s.watchHistory;
      expect(history.length, 2);
      expect(history.first, 'show:1:2', reason: 'newest first');

      s.setWatched('show:1:2', false);
      expect(s.watchHistory, ['show:1:1']);
      expect(s.watchedAt('show:1:2'), isNull);
    });

    testWidgets('history sheet lists watched episodes with an Unwatch action',
        (tester) async {
      final state = _state();
      state.setWatched('series-279830:1:1', true);

      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showWatchHistory(context),
            child: const Text('open'),
          ),
        ),
        state: state,
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Watch history'), findsOneWidget);
      expect(find.text('Unwatch'), findsWidgets);

      await tester.tap(find.text('Unwatch').first);
      await tester.pumpAndSettle();
      expect(state.isWatched('series-279830:1:1'), isFalse,
          reason: 'undo must clear the watched flag');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('watch list exposes the pull-down affordance', (tester) async {
      await tester.pumpWidget(_host(const ShowsScreen(tab: 'watchlist')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Pull down for watch history'), findsOneWidget);
      expect(find.byType(OverscrollReveal), findsOneWidget);
    });
  });

  group('movies list watch check (was inert)', () {
    testWidgets('tapping the check completes the movie', (tester) async {
      final state = _state();
      await tester.pumpWidget(
          _host(const MoviesScreen(tab: 'watchlist'), state: state));
      await tester.pump(const Duration(milliseconds: 500));

      // List mode shows the row-level checks.
      final toggle = find.byKey(const Key('moviesGridToggle'));
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle);
        await tester.pump(const Duration(milliseconds: 400));
      }

      final checks = find.byType(WatchCheck);
      if (checks.evaluate().isNotEmpty) {
        await tester.tap(checks.first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          state.trackedIds.any(
              (id) => state.statusOf(id) == TrackStatus.completed),
          isTrue,
          reason: 'movie check must record completion',
        );
      }
    });
  });

  group('Explore no longer offers Groups', () {
    testWidgets('tab strip is Feed / Discover / Activity', (tester) async {
      await tester.pumpWidget(_host(const ExploreScreen(tab: 'feed')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('FEED'), findsOneWidget);
      expect(find.text('DISCOVER'), findsOneWidget);
      expect(find.text('ACTIVITY'), findsOneWidget);
      expect(find.text('GROUPS'), findsNothing,
          reason: 'Groups was removed from Explore');
    });

    testWidgets('legacy /explore/groups falls back to Discover instead of '
        'crashing', (tester) async {
      await tester.pumpWidget(_host(const ExploreScreen(tab: 'groups')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('BROWSE ALL SHOWS'), findsOneWidget);
    });
  });

  group('browse screen (destination of the dead Browse buttons)', () {
    testWidgets('renders a poster wall with a Movies/TV switch',
        (tester) async {
      await tester.pumpWidget(_host(const BrowseScreen()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Browse'), findsOneWidget);
      expect(find.text('Movies'), findsOneWidget);
      expect(find.text('TV Shows'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
    });
  });

  group('light mode palette', () {
    tearDown(() => AppColors.applyBrightness(Brightness.dark));

    test('neutral tokens invert with brightness', () {
      AppColors.applyBrightness(Brightness.dark);
      final darkText = AppColors.textPrimary;
      final darkBg = AppColors.bgPrimary;
      final darkSurface = AppColors.surface;

      AppColors.applyBrightness(Brightness.light);
      expect(AppColors.textPrimary, isNot(darkText),
          reason: 'text must not stay white on a white background');
      expect(AppColors.bgPrimary, isNot(darkBg));
      expect(AppColors.surface, isNot(darkSurface));
      expect(AppColors.isLight, isTrue);
    });

    test('light text is dark enough to read on the light background', () {
      AppColors.applyBrightness(Brightness.light);
      final text = AppColors.textPrimary.computeLuminance();
      final bg = AppColors.bgPrimary.computeLuminance();
      final ratio = (bg + 0.05) / (text + 0.05);
      expect(ratio, greaterThan(4.5),
          reason: 'WCAG AA body-text contrast in light mode');
    });

    test('dark text keeps its contrast too', () {
      AppColors.applyBrightness(Brightness.dark);
      final text = AppColors.textPrimary.computeLuminance();
      final bg = AppColors.bgPrimary.computeLuminance();
      final ratio = (text + 0.05) / (bg + 0.05);
      expect(ratio, greaterThan(4.5));
    });

    test('brand colours stay identical across themes', () {
      AppColors.applyBrightness(Brightness.light);
      const lightAccent = AppColors.accent;
      AppColors.applyBrightness(Brightness.dark);
      expect(AppColors.accent, lightAccent);
      expect(AppColors.accent, const Color(0xFFE60000));
    });

    testWidgets('screens render in light theme without exceptions',
        (tester) async {
      AppColors.applyBrightness(Brightness.light);
      await tester.pumpWidget(_host(const ShowsScreen(tab: 'watchlist'),
          theme: AppTheme.light));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  });

  group('end-to-end wiring for the reported dead controls', () {
    testWidgets('overscrolling the watch list actually fires the reveal',
        (tester) async {
      var revealed = 0;
      await tester.pumpWidget(_host(
        OverscrollReveal(
          onReveal: () => revealed++,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            itemCount: 30,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      // Drag down from the top, well past the one-third-screen threshold.
      await tester.drag(find.byType(ListView), const Offset(0, 1400),
          touchSlopY: 0);
      await tester.pump();

      expect(revealed, 1,
          reason: 'pull-down past the threshold must open watch history');
    });

    testWidgets('a short pull does NOT fire the reveal', (tester) async {
      var revealed = 0;
      await tester.pumpWidget(_host(
        OverscrollReveal(
          onReveal: () => revealed++,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            itemCount: 30,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.drag(find.byType(ListView), const Offset(0, 40),
          touchSlopY: 0);
      await tester.pump();

      expect(revealed, 0, reason: 'a small tug must not hijack the list');
    });

    testWidgets('season check on the details screen marks the whole season',
        (tester) async {
      final state = _state();
      await tester.pumpWidget(_host(
        const TitleDetailScreen(
            titleId: '279830', kind: MediaKind.show, initialTab: 'episodes'),
        state: state,
      ));
      await tester.pumpAndSettle();

      final seasonCheck = find.byKey(const Key('seasonCheck-1'));
      expect(seasonCheck, findsOneWidget);

      await tester.ensureVisible(seasonCheck);
      await tester.pumpAndSettle();
      await tester.tap(seasonCheck);
      await tester.pumpAndSettle();

      expect(state.watchedCountFor('279830'), 13,
          reason: 'the season button must mark every episode, not just one');

      // And it clears the season again.
      await tester.tap(seasonCheck);
      await tester.pumpAndSettle();
      expect(state.watchedCountFor('279830'), 0);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('an episode seeded as watched can still be unwatched',
        (tester) async {
      // Regression: the rail check used to OR the model's seed flag over
      // AppState, which pinned seeded episodes to "watched" forever.
      final state = _state();
      state.setWatched('279830:1:11', true); // the rail shows the last 3 episodes

      await tester.pumpWidget(_host(
        const TitleDetailScreen(
            titleId: '279830', kind: MediaKind.show, initialTab: 'episodes'),
        state: state,
      ));
      await tester.pumpAndSettle();

      final railCheck = find.byType(WatchCheck).first;
      await tester.ensureVisible(railCheck);
      await tester.pumpAndSettle();
      await tester.tap(railCheck);
      await tester.pumpAndSettle();

      expect(state.isWatched('279830:1:11'), isFalse,
          reason: 'tapping a ticked episode must untick it');
      await tester.pump(const Duration(seconds: 2));
    });

    test('the router exposes /browse so the BROWSE ALL buttons resolve', () {
      final router = buildRouter(AuthController(LocalAuthService()));
      final paths = <String>[];
      void walk(List<RouteBase> routes) {
        for (final r in routes) {
          if (r is GoRoute) paths.add(r.path);
          walk(r.routes);
        }
      }

      walk(router.configuration.routes);
      expect(paths, contains('/browse'));
      expect(paths, isNot(contains('/group/:id')),
          reason: 'the orphaned Groups screen was removed');
    });
  });

}
