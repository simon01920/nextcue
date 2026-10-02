import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtrack/services/api_cache.dart';
import 'package:showtrack/services/tvdb_api.dart';

/// Body shaped like a TVDB /search response.
String _searchBody(String name) => jsonEncode({
      'status': 'success',
      'data': [
        {'objectID': 'series-1', 'name': name, 'year': '2020'}
      ],
    });

const _loginBody = '{"status":"success","data":{"token":"tok"}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('Retry-After parsing', () {
    test('uses the header value when sane', () {
      expect(TvdbApi.retryAfterDelay('3'), const Duration(seconds: 3));
    });
    test('defaults to 1s when missing or unparseable', () {
      expect(TvdbApi.retryAfterDelay(null), const Duration(seconds: 1));
      expect(TvdbApi.retryAfterDelay('soon'), const Duration(seconds: 1));
    });
    test('clamps a hostile value to 10s so the UI cannot stall', () {
      expect(TvdbApi.retryAfterDelay('9000'), const Duration(seconds: 10));
    });
  });

  group('TTL policy', () {
    test('search is short-lived, artwork long-lived', () {
      expect(TvdbApi.ttlFor('/search'), const Duration(hours: 12));
      expect(TvdbApi.ttlFor('/series/filter'), const Duration(hours: 6));
      expect(TvdbApi.ttlFor('/series/1/artworks'), const Duration(days: 7));
      expect(TvdbApi.ttlFor('/series/1/extended'), const Duration(hours: 24));
    });
  });

  test('retries once after a 429 and then succeeds', () async {
    var searchCalls = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(_loginBody, 200);
      }
      searchCalls++;
      if (searchCalls == 1) {
        return http.Response('rate limited', 429, headers: {'retry-after': '1'});
      }
      return http.Response(_searchBody('Dune'), 200);
    });

    final api = TvdbApi(client: client, cache: ApiCache(prefs));
    final results = await api.search('dune');

    expect(searchCalls, 2, reason: 'one retry after the 429');
    expect(results.first['name'], 'Dune');
  });

  test('a persistent 429 surfaces as TvdbException (no infinite retry)',
      () async {
    var searchCalls = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(_loginBody, 200);
      }
      searchCalls++;
      return http.Response('rate limited', 429, headers: {'retry-after': '1'});
    });

    final api = TvdbApi(client: client, cache: ApiCache(prefs));

    await expectLater(api.search('dune'), throwsA(isA<TvdbException>()));
    expect(searchCalls, 2, reason: 'initial attempt + exactly one retry');
  });

  test('a cache hit performs no network call at all (not even login)',
      () async {
    var networkCalls = 0;
    final client = MockClient((req) async {
      networkCalls++;
      if (req.url.path.endsWith('/login')) {
        return http.Response(_loginBody, 200);
      }
      return http.Response(_searchBody('Arrival'), 200);
    });

    final cache = ApiCache(prefs);
    final first = TvdbApi(client: client, cache: cache);
    await first.search('arrival');
    final callsAfterFirst = networkCalls;
    expect(callsAfterFirst, greaterThan(0));

    // A brand-new client sharing the cache must not touch the network.
    final second = TvdbApi(client: client, cache: cache);
    final results = await second.search('arrival');

    expect(results.first['name'], 'Arrival');
    expect(networkCalls, callsAfterFirst,
        reason: 'cached response must skip both login and the request');
  });

  test('failed responses are never cached', () async {
    var attempts = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(_loginBody, 200);
      }
      attempts++;
      if (attempts == 1) return http.Response('boom', 500);
      return http.Response(_searchBody('Solaris'), 200);
    });

    final api = TvdbApi(client: client, cache: ApiCache(prefs));

    await expectLater(api.search('solaris'), throwsA(isA<TvdbException>()));
    final results = await api.search('solaris');
    expect(results.first['name'], 'Solaris',
        reason: 'the error must not have been cached');
  });
}
