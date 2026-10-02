import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtrack/services/api_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('serves a memory hit without re-fetching', () async {
    final cache = ApiCache(prefs);
    var calls = 0;
    Future<String> fetch() async {
      calls++;
      return '{"v":1}';
    }

    final a = await cache.through(
        key: 'k', ttl: const Duration(hours: 1), fetch: fetch);
    final b = await cache.through(
        key: 'k', ttl: const Duration(hours: 1), fetch: fetch);

    expect(a, '{"v":1}');
    expect(b, '{"v":1}');
    expect(calls, 1, reason: 'second call must be served from cache');
  });

  test('re-fetches once the TTL has expired', () async {
    var now = DateTime(2026, 1, 1, 12);
    final cache = ApiCache(prefs, clock: () => now);
    var calls = 0;
    Future<String> fetch() async => '{"n":${++calls}}';

    await cache.through(
        key: 'k', ttl: const Duration(minutes: 30), fetch: fetch);
    now = now.add(const Duration(minutes: 31));
    final second = await cache.through(
        key: 'k', ttl: const Duration(minutes: 30), fetch: fetch);

    expect(calls, 2);
    expect(second, '{"n":2}');
  });

  test('survives a restart by reading the persisted entry', () async {
    final first = ApiCache(prefs);
    await first.through(
        key: 'persist', ttl: const Duration(hours: 6), fetch: () async => 'body');

    // New instance = new memory tier, same prefs backing store.
    final second = ApiCache(prefs);
    var calls = 0;
    final body = await second.through(
      key: 'persist',
      ttl: const Duration(hours: 6),
      fetch: () async {
        calls++;
        return 'network';
      },
    );

    expect(body, 'body');
    expect(calls, 0, reason: 'persisted entry should avoid the network');
  });

  test('coalesces concurrent identical requests into one fetch', () async {
    final cache = ApiCache(prefs);
    var calls = 0;
    Future<String> slowFetch() async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 'shared';
    }

    final results = await Future.wait([
      cache.through(key: 'same', ttl: const Duration(hours: 1), fetch: slowFetch),
      cache.through(key: 'same', ttl: const Duration(hours: 1), fetch: slowFetch),
      cache.through(key: 'same', ttl: const Duration(hours: 1), fetch: slowFetch),
    ]);

    expect(results, ['shared', 'shared', 'shared']);
    expect(calls, 1, reason: 'in-flight requests must be shared');
  });

  test('keeps oversized entries in memory only', () async {
    final cache = ApiCache(prefs, maxEntryBytes: 32);
    final big = 'x' * 200;
    await cache.through(
        key: 'big', ttl: const Duration(hours: 1), fetch: () async => big);

    expect(cache.persistedBytes, 0);
    // Still served from the memory tier.
    var calls = 0;
    final again = await cache.through(
      key: 'big',
      ttl: const Duration(hours: 1),
      fetch: () async {
        calls++;
        return 'other';
      },
    );
    expect(again, big);
    expect(calls, 0);
  });

  test('evicts least-recently-used entries to stay under budget', () async {
    var now = DateTime(2026, 1, 1);
    final cache = ApiCache(prefs, totalBudgetBytes: 250, maxEntryBytes: 200);
    final body = 'y' * 100;

    Future<void> put(String k) async {
      now = now.add(const Duration(seconds: 1));
      await cache.through(
          key: k, ttl: const Duration(hours: 1), fetch: () async => body);
    }

    await put('a');
    await put('b');
    await put('c'); // 300 bytes > 250 budget → oldest ('a') evicted

    expect(cache.persistedBytes, lessThanOrEqualTo(250));
    expect(prefs.getString('${ApiCache.keyPrefix}e.${ApiCache.hashKey('a')}'),
        isNull);
    expect(prefs.getString('${ApiCache.keyPrefix}e.${ApiCache.hashKey('c')}'),
        isNotNull);
  });

  test('clear() removes every persisted entry', () async {
    final cache = ApiCache(prefs);
    await cache.through(
        key: 'k1', ttl: const Duration(hours: 1), fetch: () async => 'a');
    await cache.through(
        key: 'k2', ttl: const Duration(hours: 1), fetch: () async => 'b');
    expect(cache.persistedBytes, greaterThan(0));

    await cache.clear();

    expect(cache.persistedBytes, 0);
    expect(prefs.getKeys().where((k) => k.startsWith(ApiCache.keyPrefix)),
        isEmpty);
    // And a subsequent read goes back to the network.
    var calls = 0;
    await cache.through(
      key: 'k1',
      ttl: const Duration(hours: 1),
      fetch: () async {
        calls++;
        return 'fresh';
      },
    );
    expect(calls, 1);
  });

  test('a failed fetch is not cached and does not block a retry', () async {
    final cache = ApiCache(prefs);
    var attempts = 0;

    await expectLater(
      cache.through(
        key: 'flaky',
        ttl: const Duration(hours: 1),
        fetch: () async {
          attempts++;
          throw Exception('boom');
        },
      ),
      throwsException,
    );

    final body = await cache.through(
      key: 'flaky',
      ttl: const Duration(hours: 1),
      fetch: () async {
        attempts++;
        return 'recovered';
      },
    );

    expect(body, 'recovered');
    expect(attempts, 2, reason: 'in-flight entry must clear after a failure');
  });
}
