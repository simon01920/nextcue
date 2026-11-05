import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtrack/data/mock_repository.dart';
import 'package:showtrack/data/repository.dart';
import 'package:showtrack/models/models.dart';
import 'package:showtrack/screens/search_screen.dart';
import 'package:showtrack/services/anilist_api.dart';
import 'package:showtrack/services/api_cache.dart';
import 'package:showtrack/services/rate_limiter.dart';
import 'package:showtrack/state/app_state.dart';
import 'package:showtrack/theme/app_theme.dart';

/// Cover for "don't get the app blocked by the APIs": request budget,
/// 429 cooldown, stale-cache fallback and search throttling.

class _CountingRepo extends MockRepository {
  _CountingRepo();
  final List<String> queries = [];
  @override
  Future<List<MediaTitle>> search(String query, MediaKind? kind) {
    queries.add(query);
    return super.search(query, kind);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RateLimiter', () {
    test('never exceeds the window budget', () async {
      var now = DateTime(2026);
      final l = RateLimiter(
          maxRequests: 3,
          per: const Duration(seconds: 1),
          maxWait: Duration.zero,
          clock: () => now);
      for (var i = 0; i < 3; i++) {
        await l.run(() async => i);
      }
      await expectLater(
          l.run(() async => 4), throwsA(isA<RateLimitedException>()));
      now = now.add(const Duration(seconds: 1));
      expect(await l.run(() async => 5), 5);
    });

    test('a 429 cooldown blocks everything until it ends', () async {
      var now = DateTime(2026);
      final l = RateLimiter(
          maxRequests: 100,
          per: const Duration(minutes: 1),
          maxWait: Duration.zero,
          clock: () => now);
      l.cooldown(const Duration(seconds: 30));
      expect(l.coolingDown, isTrue);
      await expectLater(
          l.run(() async => 1), throwsA(isA<RateLimitedException>()));
      now = now.add(const Duration(seconds: 31));
      expect(await l.run(() async => 2), 2);
    });

    test('caps concurrent requests', () async {
      final l = RateLimiter(
          maxRequests: 100, per: const Duration(minutes: 1), maxConcurrent: 2);
      var active = 0, peak = 0;
      await Future.wait(List.generate(6, (_) => l.run(() async {
            active++;
            if (active > peak) peak = active;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            active--;
          })));
      expect(peak, 2);
    });

    test('reads Retry-After and X-RateLimit-Reset', () {
      final now = DateTime(2026);
      expect(retryAfter({'retry-after': '12'}), const Duration(seconds: 12));
      final reset = now.add(const Duration(seconds: 40));
      expect(
          retryAfter(
              {'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}'},
              now: now),
          const Duration(seconds: 40));
      expect(retryAfter({'retry-after': '99999'}), const Duration(minutes: 2));
    });
  });

  group('ApiCache stale fallback', () {
    test('serves the expired copy when the fetch fails', () async {
      var now = DateTime(2026);
      final cache =
          ApiCache(await SharedPreferences.getInstance(), clock: () => now);
      Future<String> get(Future<String> Function() f) =>
          cache.through(key: 'k', ttl: const Duration(hours: 1), fetch: f);
      expect(await get(() async => 'fresh'), 'fresh');
      now = now.add(const Duration(hours: 5)); // expired
      expect(await get(() async => throw Exception('HTTP 500')), 'fresh');
      expect(cache.staleServed, 1);
    });

    test('too-old copies are not served', () async {
      var now = DateTime(2026);
      final cache =
          ApiCache(await SharedPreferences.getInstance(), clock: () => now);
      await cache.through(
          key: 'k', ttl: const Duration(hours: 1), fetch: () async => 'old');
      now = now.add(const Duration(days: 40));
      await expectLater(
          cache.through(
              key: 'k',
              ttl: const Duration(hours: 1),
              fetch: () async => throw Exception('offline')),
          throwsException);
    });
  });

  test('AniList 429 pauses further requests and falls back to cache',
      () async {
    var calls = 0;
    var limited = false;
    final client = MockClient((req) async {
      calls++;
      if (limited) {
        return http.Response('{}', 429, headers: {'retry-after': '60'});
      }
      return http.Response('{"data":{"Page":{"media":[]}}}', 200);
    });
    var now = DateTime(2026);
    final api = AniListApi(
      client: client,
      cache: ApiCache(await SharedPreferences.getInstance(), clock: () => now),
      limiter: RateLimiter(
          maxRequests: 50,
          per: const Duration(minutes: 1),
          maxWait: Duration.zero),
    );
    await api.searchAnime('lost');
    now = now.add(const Duration(days: 1)); // cache expired
    limited = true;
    await api.searchAnime('lost'); // 429 → stale copy, cooldown starts
    expect(api.limiter.coolingDown, isTrue);
    final before = calls;
    await api.searchAnime('other'); // blocked locally, no request sent
    expect(calls, before);
  });

  group('search screen', () {
    Future<_CountingRepo> pump(WidgetTester tester) async {
      final repo = _CountingRepo();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
          Provider<ContentRepository>.value(value: repo),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const SearchScreen()),
      ));
      await tester.pump();
      return repo;
    }

    testWidgets('typing a word sends one request after the pause',
        (tester) async {
      final repo = await pump(tester);
      repo.queries.clear(); // initial trending load
      for (final partial in ['b', 'br', 'bre', 'brea', 'break']) {
        await tester.enterText(find.byType(TextField), partial);
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(repo.queries, isEmpty);
      await tester.pump(SearchScreen.searchDelay);
      expect(repo.queries, ['break']);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('one letter is not sent', (tester) async {
      final repo = await pump(tester);
      repo.queries.clear();
      await tester.enterText(find.byType(TextField), 'b');
      await tester.pump(const Duration(seconds: 1));
      expect(repo.queries, isEmpty);
      expect(find.text('Keep typing…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('same query typed differently is sent once', (tester) async {
      final repo = await pump(tester);
      repo.queries.clear();
      await tester.enterText(find.byType(TextField), 'Lost');
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), ' lost  ');
      await tester.pump(const Duration(seconds: 1));
      expect(repo.queries, ['lost']);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
