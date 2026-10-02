import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:showtrack/data/mock_repository.dart';
import 'package:showtrack/data/repository.dart';
import 'package:showtrack/state/app_state.dart';
import 'package:showtrack/theme/app_theme.dart';
import 'package:showtrack/screens/shows_screen.dart';

Widget _host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        Provider<ContentRepository>(create: (_) => const MockRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('golden: shows watch list', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_host(const ShowsScreen(tab: 'watchlist')));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byKey(const Key('showsScreen')),
      matchesGoldenFile('golden/shows_watchlist.png'),
    );
  });
}
