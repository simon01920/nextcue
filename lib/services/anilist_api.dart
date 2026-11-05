import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_cache.dart';
import 'rate_limiter.dart';

/// AniList public GraphQL client (no key required, CORS-enabled).
/// Primary anime metadata + artwork source per 00-config.json, and the
/// keyless catalog fallback for search/trending/detail whenever TheTVDB
/// API key isn't configured.
///
/// Responses route through [ApiCache] when supplied — AniList is generous
/// but rate-limited, and the For You screen resolves the same ids repeatedly.
class AniListApi {
  AniListApi({http.Client? client, ApiCache? cache, RateLimiter? limiter})
    : _client = client ?? http.Client(),
      _cache = cache,
      limiter =
          limiter ??
          RateLimiter(
            maxRequests: 25,
            per: const Duration(minutes: 1),
            maxConcurrent: 3,
          );

  /// AniList allows 90 requests/minute per IP (temporarily lowered to 30 at
  /// times); stay under the lower figure. A 429 pauses every request.
  final RateLimiter limiter;

  static const String _endpoint = 'https://graphql.anilist.co';
  final http.Client _client;
  final ApiCache? _cache;

  /// A stalled connection must end in the error/empty state, not an endless
  /// spinner.
  static const Duration requestTimeout = Duration(seconds: 15);
  static const Duration ttlTrending = Duration(hours: 6);
  static const Duration ttlSearch = Duration(hours: 12);
  static const Duration ttlMedia = Duration(hours: 24);

  /// POSTs a GraphQL document, optionally served from cache. The cache key is
  /// the query text plus its variables, so different variables never collide.
  Future<String?> _post(
    String query,
    Map<String, dynamic> variables,
    Duration ttl,
  ) async {
    Future<String> fetch() => limiter.run(() async {
      final res = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query, 'variables': variables}),
          )
          .timeout(requestTimeout);
      if (res.statusCode == 429) {
        limiter.cooldown(
          retryAfter(res.headers, fallback: const Duration(seconds: 60)),
        );
        throw AniListException('HTTP 429 (rate limited)');
      }
      if (res.statusCode != 200) {
        throw AniListException('HTTP ${res.statusCode}');
      }
      return res.body;
    });

    try {
      final cache = _cache;
      if (cache == null) return await fetch();
      return await cache.through(
        key: 'anilist:${ApiCache.hashKey(query)}:${jsonEncode(variables)}',
        ttl: ttl,
        fetch: fetch,
      );
    } catch (_) {
      return null;
    }
  }

  static const String _mediaFields = r'''
    id
    title { romaji english }
    coverImage { large extraLarge }
    bannerImage
    description(asHtml: false)
    genres
    averageScore
    format
    status
    episodes
    startDate { year month day }
    nextAiringEpisode { episode airingAt }
    streamingEpisodes { title thumbnail }
  ''';

  Future<List<AniListMedia>> _page(
    String query,
    Map<String, dynamic> variables, {
    Duration ttl = ttlSearch,
  }) async {
    final raw = await _post(query, variables, ttl);
    if (raw == null) return const [];
    final body = jsonDecode(raw) as Map<String, dynamic>;
    final media =
        (((body['data'] as Map<String, dynamic>?)?['Page']
                as Map<String, dynamic>?)?['media']
            as List?) ??
        const [];
    return media
        .cast<Map<String, dynamic>>()
        .map(AniListMedia.fromJson)
        .toList();
  }

  /// Trending anime. [format] narrows to 'TV', 'MOVIE', etc.; null = any.
  Future<List<AniListMedia>> trendingAnime({int perPage = 12, String? format}) {
    const query = '''
      query (\$perPage: Int, \$format: MediaFormat) {
        Page(page: 1, perPage: \$perPage) {
          media(sort: TRENDING_DESC, type: ANIME, format: \$format) {
            $_mediaFields
          }
        }
      }
    ''';
    return _page(query, {
      'perPage': perPage,
      if (format != null) 'format': format,
    }, ttl: ttlTrending);
  }

  /// Full-text search. [format] narrows to 'TV' / 'MOVIE'; null = any.
  Future<List<AniListMedia>> searchAnime(
    String search, {
    int perPage = 25,
    String? format,
  }) {
    const query = '''
      query (\$search: String, \$perPage: Int, \$format: MediaFormat) {
        Page(page: 1, perPage: \$perPage) {
          media(search: \$search, type: ANIME, sort: SEARCH_MATCH,
                format: \$format) {
            $_mediaFields
          }
        }
      }
    ''';
    return _page(query, {
      'search': search,
      'perPage': perPage,
      if (format != null) 'format': format,
    });
  }

  /// Single title with full metadata (episode counts, schedule, stills).
  Future<AniListMedia?> mediaById(int id) async {
    const query = '''
      query (\$id: Int) {
        Media(id: \$id, type: ANIME) {
          $_mediaFields
        }
      }
    ''';
    final raw = await _post(query, {'id': id}, ttlMedia);
    if (raw == null) return null;
    final body = jsonDecode(raw) as Map<String, dynamic>;
    final media =
        (body['data'] as Map<String, dynamic>?)?['Media']
            as Map<String, dynamic>?;
    return media == null ? null : AniListMedia.fromJson(media);
  }
}

class AniListException implements Exception {
  final String message;
  AniListException(this.message);
  @override
  String toString() => 'AniListException: $message';
}

class AniListStreamingEpisode {
  final String title;
  final String? thumbnail;
  const AniListStreamingEpisode({required this.title, this.thumbnail});
}

class AniListMedia {
  final int id;
  final String name;
  final String? poster;
  final String? banner;
  final String? description;
  final List<String> genres;
  final int? score;
  final String? format; // TV, MOVIE, OVA…
  final String? status; // FINISHED, RELEASING…
  final int? episodes;
  final DateTime? startDate;
  final int? nextEpisodeNumber;
  final DateTime? nextEpisodeAiring;
  final List<AniListStreamingEpisode> streamingEpisodes;

  const AniListMedia({
    required this.id,
    required this.name,
    this.poster,
    this.banner,
    this.description,
    this.genres = const [],
    this.score,
    this.format,
    this.status,
    this.episodes,
    this.startDate,
    this.nextEpisodeNumber,
    this.nextEpisodeAiring,
    this.streamingEpisodes = const [],
  });

  bool get isMovie => format == 'MOVIE';

  factory AniListMedia.fromJson(Map<String, dynamic> j) {
    final title = j['title'] as Map<String, dynamic>? ?? const {};
    final cover = j['coverImage'] as Map<String, dynamic>? ?? const {};
    final start = j['startDate'] as Map<String, dynamic>?;
    final next = j['nextAiringEpisode'] as Map<String, dynamic>?;
    final airingAt = next?['airingAt'] as int?;
    return AniListMedia(
      id: j['id'] as int? ?? 0,
      name: (title['english'] ?? title['romaji'] ?? 'Unknown') as String,
      poster: (cover['extraLarge'] ?? cover['large']) as String?,
      banner: j['bannerImage'] as String?,
      description: (j['description'] as String?)
          ?.replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), ''),
      genres: (j['genres'] as List? ?? const []).cast<String>(),
      score: j['averageScore'] as int?,
      format: j['format'] as String?,
      status: j['status'] as String?,
      episodes: j['episodes'] as int?,
      startDate:
          start == null || start['year'] == null
              ? null
              : DateTime(
                start['year'] as int,
                start['month'] as int? ?? 1,
                start['day'] as int? ?? 1,
              ),
      nextEpisodeNumber: next?['episode'] as int?,
      nextEpisodeAiring:
          airingAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
      streamingEpisodes:
          (j['streamingEpisodes'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(
                (e) => AniListStreamingEpisode(
                  title: e['title'] as String? ?? '',
                  thumbnail: e['thumbnail'] as String?,
                ),
              )
              .toList(),
    );
  }
}
