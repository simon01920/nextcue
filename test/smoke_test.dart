import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:showtrack/data/mock_repository.dart';
import 'package:showtrack/data/repository.dart';
import 'package:showtrack/state/app_state.dart';
import 'package:showtrack/theme/app_theme.dart';
import 'package:showtrack/theme/tokens.dart';
import 'package:showtrack/screens/shows_screen.dart';

/// Wraps a screen in the minimal app context (theme + providers) for testing.
Widget _host(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AppState()),
      Provider<ContentRepository>(create: (_) => const MockRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('Shows screen renders watch list without exceptions',
      (tester) async {
    await tester.pumpWidget(_host(const ShowsScreen(tab: 'watchlist')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('showsScreen')), findsOneWidget);
    expect(find.text('WATCH LIST'), findsOneWidget);
    expect(find.text('UPCOMING'), findsOneWidget);
  });

  testWidgets('Watch-list categorization chips are present after load',
      (tester) async {
    await tester.pumpWidget(_host(const ShowsScreen(tab: 'watchlist')));
    await tester.pump(const Duration(milliseconds: 300));
    // Mock entries have no watched episodes, so they land in NOT STARTED.
    expect(find.text('NOT STARTED'), findsOneWidget);
  });

  test('Design tokens: Bingely red rebrand + measured surfaces', () {
    // Accent rebranded to Bingely red; every other token stays the
    // measured TV Time value.
    expect(AppColors.accent, const Color(0xFFE60000));
    expect(AppColors.accentInk, const Color(0xFFFFFFFF));
    expect(AppColors.bgPrimary, const Color(0xFF000000));
    expect(AppColors.surface, const Color(0xFF202020));
    expect(AppColors.success, const Color(0xFF66CC00));
    expect(AppColors.link, const Color(0xFF1A75FF));
  });

  test('Watched-state toggle flips through AppState', () {
    final s = AppState();
    expect(s.isWatched('e1'), isFalse);
    s.toggleWatched('e1');
    expect(s.isWatched('e1'), isTrue);
    s.toggleWatched('e1');
    expect(s.isWatched('e1'), isFalse);
  });
}
