import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:http/http.dart' as http;

import 'api_cache.dart';

/// One way to watch a title (a streaming service, rental or purchase).
class WatchOffer {
  final String service;
  final String iconUrl;
  final String url;

  /// FLATRATE (subscription), FREE, ADS, RENT or BUY.
  final String type;
  const WatchOffer({
    required this.service,
    required this.iconUrl,
    required this.url,
    required this.type,
  });
}

/// Where-to-watch from JustWatch's public GraphQL endpoint.
///
/// shortcut: this is JustWatch's unofficial API (no key, CORS-enabled, used by
/// their own site); it can change or start blocking without notice, so every
/// failure degrades to an empty list. Move to a licensed source (JustWatch
/// partner API or TMDB watch providers) before a commercial release.
class JustWatchApi {
  JustWatchApi({http.Client? client, ApiCache? cache})
      : _client = client ?? http.Client(),
        _cache = cache;

  final http.Client _client;
  final ApiCache? _cache;

  static const _endpoint = 'https://apis.justwatch.com/graphql';
  static const _query = r'''
query S($f: TitleFilter!, $country: Country!, $language: Language!) {
  popularTitles(country: $country, filter: $f, first: 5) {
    edges { node {
      content(country: $country, language: $language) { originalReleaseYear }
      offers(country: $country, platform: WEB) {
        monetizationType standardWebURL
        package { clearName icon(profile: S100) }
      }
    } }
  }
}''';

  /// The device's country, else Slovakia (where most users are).
  static String get country {
    final c = PlatformDispatcher.instance.locale.countryCode;
    return c == null || c.isEmpty ? 'SK' : c.toUpperCase();
  }

  Future<List<WatchOffer>> offers({
    required String name,
    required bool isShow,
    int? year,
    String? countryCode,
  }) async {
    final vars = {
      'f': {
        'searchQuery': name,
        'objectTypes': [isShow ? 'SHOW' : 'MOVIE'],
      },
      'country': countryCode ?? country,
      'language': 'en',
    };
    Future<String> fetch() async {
      final res = await _client
          .post(Uri.parse(_endpoint),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'query': _query, 'variables': vars}))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception('JustWatch ${res.statusCode}');
      return res.body;
    }

    try {
      final cache = _cache;
      final body = cache == null
          ? await fetch()
          : await cache.through(
              key: 'justwatch:${jsonEncode(vars)}',
              ttl: const Duration(hours: 24),
              fetch: fetch);
      return parseOffers(body, year: year);
    } catch (_) {
      return const [];
    }
  }

  /// Picks the search result released in [year] (else the top one) and
  /// returns one offer per service, cheapest way first.
  static List<WatchOffer> parseOffers(String body, {int? year}) {
    final edges = (((jsonDecode(body) as Map)['data'] as Map?)?['popularTitles']
            as Map?)?['edges'] as List? ??
        const [];
    if (edges.isEmpty) return const [];
    Map node(dynamic e) => (e as Map)['node'] as Map;
    final match = edges.map(node).firstWhere(
          (n) => year != null && (n['content'] as Map?)?['originalReleaseYear'] == year,
          orElse: () => node(edges.first),
        );
    const rank = {'FREE': 0, 'ADS': 1, 'FLATRATE': 2, 'RENT': 3, 'BUY': 4};
    final offers = [
      for (final o in (match['offers'] as List? ?? const []).cast<Map>())
        WatchOffer(
          service: (o['package'] as Map)['clearName'] as String,
          iconUrl: 'https://images.justwatch.com'
              '${((o['package'] as Map)['icon'] as String).replaceAll('{format}', 'png')}',
          url: o['standardWebURL'] as String? ?? '',
          type: o['monetizationType'] as String? ?? '',
        ),
    ]..sort((a, b) => (rank[a.type] ?? 9).compareTo(rank[b.type] ?? 9));
    final seen = <String>{};
    return [for (final o in offers) if (seen.add(o.service)) o];
  }
}
