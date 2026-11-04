import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtrack/data/tvdb_repository.dart';
import 'package:showtrack/services/anilist_api.dart';
import 'package:showtrack/services/tvdb_api.dart';
import 'package:showtrack/state/app_state.dart';

/// Cover for the smoothness/perf pass: memoized futures, parallel loads,
/// one shared TVDB login, episode pagination and coalesced persistence.

const _loginBody = '{"status":"success","data":{"token":"tok"}}';

Map<String, dynamic> _ep(int s, int n) => {
      'seasonNumber': s,
      'number': n,
      'name': 'E$n',
      'aired': '2001-01-01',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TvdbRepository', () {
    late int logins;
    late Map<String, int> gets;
    late TvdbRepository repo;
    late AppState state;

    setUp(() async {
      logins = 0;
      gets = {};
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/login')) {
          logins++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return http.Response(_loginBody, 200);
        }
        gets.update(req.url.path, (v) => v + 1, ifAbsent: () => 1);
        final path = req.url.path;
        if (path.contains('/episodes/')) {
          final page = int.parse(req.url.queryParameters['page'] ?? '0');
          // Page 0 is full (500), page 1 holds the rest.
          final eps = page == 0
              ? [for (var i = 1; i <= 500; i++) _ep(1, i)]
              : [for (var i = 501; i <= 520; i++) _ep(1, i)];
          return http.Response(
              jsonEncode({
                'data': {'episodes': eps}
              }),
              200);
        }
        if (path.contains('/extended')) {
          return http.Response(
              jsonEncode({
                'data': {'name': 'Show ${path.split('/')[3]}'}
              }),
              200);
        }
        return http.Response('{"data":[]}', 200);
      });
      state = AppState();
      await state.bind('u1');
      repo = TvdbRepository(
        tvdb: TvdbApi(client: client),
        anilist: AniListApi(client: client),
        appState: state,
      );
    });

    test('same title returns the identical future (no FutureBuilder restart)',
        () async {
      final a = repo.titleById('series-1');
      final b = repo.titleById('series-1');
      expect(identical(a, b), isTrue);
      await a;
      expect(identical(repo.titleById('series-1'), a), isTrue);
      expect(gets['/v4/series/1/extended'], 1);
    });

    test('long shows load every episode page', () async {
      final t = await repo.titleById('series-1');
      expect(t.seasons.single.episodes.length, 520);
    });

    test('parallel watch-list load shares a single login', () async {
      for (var i = 1; i <= 5; i++) {
        state.setStatus('series-$i', TrackStatus.watching);
      }
      final list = await repo.showWatchlist();
      expect(list.map((e) => e.title.id),
          ['series-1', 'series-2', 'series-3', 'series-4', 'series-5']);
      expect(logins, 1);
    });

    test('a failed title load is retried on the next call', () async {
      var fail = true;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/login')) {
          return http.Response(_loginBody, 200);
        }
        if (fail) return http.Response('nope', 500);
        if (req.url.path.contains('/episodes/')) {
          return http.Response('{"data":{"episodes":[]}}', 200);
        }
        return http.Response('{"data":{"name":"Ok"}}', 200);
      });
      final r = TvdbRepository(
          tvdb: TvdbApi(client: client),
          anilist: AniListApi(client: client),
          appState: state);
      await expectLater(r.titleById('series-9'), throwsA(isA<TvdbException>()));
      fail = false;
      expect((await r.titleById('series-9')).name, 'Ok');
    });
  });

  group('AppState', () {
    test('watchedCountFor stays in step with toggles and bulk marks', () async {
      final s = AppState();
      await s.bind('u');
      s.setManyWatched(['a:1:1', 'a:1:2', 'a:1:3', 'b:1:1'], true);
      expect(s.watchedCountFor('a'), 3);
      expect(s.watchedCountFor('b'), 1);
      s.toggleWatched('a:1:2');
      expect(s.watchedCountFor('a'), 2);
      s.setWatched('a:1:1', true); // already watched: no double count
      expect(s.watchedCountFor('a'), 2);
      s.setManyWatched(['a:1:1', 'a:1:3'], false);
      expect(s.watchedCountFor('a'), 0);
      // 'ab' must not be counted as part of 'a'.
      s.setWatched('ab:1:1', true);
      expect(s.watchedCountFor('a'), 0);
    });

    test('writes are coalesced and survive a reload', () async {
      final s = AppState();
      await s.bind('u');
      s.setManyWatched(['x:1:1', 'x:1:2'], true);
      s.rate('x:1:1', 4);
      s.setStatus('x', TrackStatus.watching);
      await Future<void>.delayed(Duration.zero);

      final reloaded = AppState();
      await reloaded.bind('u');
      expect(reloaded.watchedCountFor('x'), 2);
      expect(reloaded.ratingOf('x:1:1'), 4);
      expect(reloaded.statusOf('x'), TrackStatus.watching);
    });

    test('switching accounts flushes pending writes to the old account',
        () async {
      final s = AppState();
      await s.bind('alice');
      s.setStatus('t', TrackStatus.completed);
      // No await: the write is still queued when the account changes.
      await s.bind('bob');
      expect(s.statusOf('t'), isNull);
      await s.bind('alice');
      expect(s.statusOf('t'), TrackStatus.completed);
    });
  });
}
