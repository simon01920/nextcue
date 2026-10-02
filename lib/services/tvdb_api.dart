import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_cache.dart';

/// Thin TheTVDB v4 client. The API key is injected at build time via
/// --dart-define=TVDB_API_KEY=... and is never committed as a literal
/// (contract §9). CORS verified: api4.thetvdb.com allows browser calls.
///
/// Responses are served through [ApiCache] when one is supplied, so repeat
/// requests never re-spend the free-tier quota. Cache hits skip both the
/// network and the token refresh.
class TvdbApi {
  TvdbApi({http.Client? client, ApiCache? cache})
      : _client = client ?? http.Client(),
        _cache = cache;

  static const String _base = 'https://api4.thetvdb.com/v4';
  static const String apiKey = String.fromEnvironment('TVDB_API_KEY');

  String? _token;
  DateTime _tokenTime = DateTime.fromMillisecondsSinceEpoch(0);
  final http.Client _client;
  final ApiCache? _cache;

  bool get isConfigured => apiKey.isNotEmpty;

  /// How long each endpoint class stays fresh. Artwork and episode lists
  /// change rarely; trending shifts through the day.
  static Duration ttlFor(String path) {
    if (path.startsWith('/search')) return const Duration(hours: 12);
    if (path.contains('/filter')) return const Duration(hours: 6);
    if (path.contains('/artworks')) return const Duration(days: 7);
    return const Duration(hours: 24);
  }

  Future<String> _login() async {
    final res = await _client.post(
      Uri.parse('$_base/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'apikey': apiKey}),
    );
    if (res.statusCode != 200) {
      throw TvdbException('login failed: HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['data'] as Map<String, dynamic>)['token'] as String;
  }

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final cache = _cache;
    if (cache == null) {
      return jsonDecode(await _fetchRaw(path, uri)) as Map<String, dynamic>;
    }
    final body = await cache.through(
      key: uri.toString(),
      ttl: ttlFor(path),
      fetch: () => _fetchRaw(path, uri),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Performs the actual request, refreshing the token when needed and
  /// honouring a single `Retry-After` backoff on HTTP 429. Returns the raw
  /// body so the cache can store it verbatim; only 200s ever get here.
  Future<String> _fetchRaw(String path, Uri uri) async {
    if (_token == null ||
        DateTime.now().difference(_tokenTime) > const Duration(hours: 20)) {
      _token = await _login();
      _tokenTime = DateTime.now();
    }
    var res =
        await _client.get(uri, headers: {'Authorization': 'Bearer $_token'});
    if (res.statusCode == 401) {
      _token = await _login();
      _tokenTime = DateTime.now();
      res =
          await _client.get(uri, headers: {'Authorization': 'Bearer $_token'});
    }
    if (res.statusCode == 429) {
      final wait = retryAfterDelay(res.headers['retry-after']);
      await Future<void>.delayed(wait);
      res =
          await _client.get(uri, headers: {'Authorization': 'Bearer $_token'});
    }
    if (res.statusCode != 200) {
      throw TvdbException('GET $path failed: HTTP ${res.statusCode}');
    }
    return res.body;
  }

  /// Parses a `Retry-After` header (seconds) and clamps it to a sane window
  /// so a hostile value can't stall the UI.
  static Duration retryAfterDelay(String? header) {
    final secs = int.tryParse(header?.trim() ?? '') ?? 1;
    return Duration(seconds: secs.clamp(1, 10));
  }

  /// /search — type: 'series' | 'movie' | null (both).
  Future<List<Map<String, dynamic>>> search(String query,
      {String? type, int limit = 25}) async {
    final body = await _get('/search', {
      'query': query,
      if (type != null) 'type': type,
      'limit': '$limit',
    });
    return (body['data'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  /// /series/filter sorted by score — the "trending" source.
  Future<List<Map<String, dynamic>>> trendingSeries() async {
    final body = await _get('/series/filter', {
      'country': 'usa',
      'lang': 'eng',
      'sort': 'score',
      'sortType': 'desc',
    });
    return (body['data'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> trendingMovies() async {
    final body = await _get('/movies/filter', {
      'country': 'usa',
      'lang': 'eng',
      'sort': 'score',
      'sortType': 'desc',
    });
    return (body['data'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  /// /series/{id}/extended — series meta incl. characters, artworks and
  /// name/overview translations (meta=translations).
  Future<Map<String, dynamic>> seriesExtended(int id) async {
    final body =
        await _get('/series/$id/extended', {'meta': 'translations'});
    return (body['data'] as Map<String, dynamic>?) ?? const {};
  }

  /// /series/{id}/episodes/default/eng — episode list with English names.
  Future<List<Map<String, dynamic>>> seriesEpisodes(int id,
      {int page = 0}) async {
    final body =
        await _get('/series/$id/episodes/default/eng', {'page': '$page'});
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    return (data['episodes'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  /// /series/{id}/artworks — full artwork list (posters type 2,
  /// backgrounds/banners type 3, wide banners type 1).
  Future<List<Map<String, dynamic>>> seriesArtworks(int id) async {
    final body = await _get('/series/$id/artworks', {'lang': 'eng'});
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    return (data['artworks'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> movieExtended(int id) async {
    final body = await _get('/movies/$id/extended');
    return (body['data'] as Map<String, dynamic>?) ?? const {};
  }

  static String? absoluteImage(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return 'https://artworks.thetvdb.com$path';
  }
}

class TvdbException implements Exception {
  final String message;
  TvdbException(this.message);
  @override
  String toString() => 'TvdbException: $message';
}
