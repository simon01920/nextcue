import '../models/models.dart';
import '../services/anilist_api.dart';
import '../services/tvdb_api.dart';
import '../state/app_state.dart';
import 'repository.dart';

/// Live repository: TheTVDB primary (movies + TV), AniList for the anime
/// rail. Watch list / upcoming derive from the signed-in account's tracked
/// statuses in AppState. Titles cached in memory per session.
///
/// When no TVDB_API_KEY is configured, AniList (keyless, CORS-enabled)
/// takes over search / trending / detail so the app stays fully usable —
/// those titles use canonical ids 'series-al-<n>' / 'movie-al-<n>'.
class TvdbRepository implements ContentRepository {
  final TvdbApi tvdb;
  final AniListApi anilist;
  final AppState appState;

  TvdbRepository({
    required this.tvdb,
    required this.anilist,
    required this.appState,
  });

  final Map<String, MediaTitle> _cache = {};

  // ---- id helpers: canonical ids are 'series-279830' / 'movie-231' for
  // TVDB and 'series-al-21' / 'movie-al-21' for AniList-backed titles.
  static final RegExp _aniListId = RegExp(r'^(series|movie)-al-(\d+)$');

  static (MediaKind, int)? parseAniListId(String id) {
    final m = _aniListId.firstMatch(id);
    if (m == null) return null;
    return (
      m.group(1) == 'movie' ? MediaKind.movie : MediaKind.show,
      int.parse(m.group(2)!),
    );
  }

  static (MediaKind, int)? parseId(String id) {
    final parts = id.split('-');
    if (parts.length < 2) return null;
    final num = int.tryParse(parts.last);
    if (num == null) return null;
    return (parts.first == 'movie' ? MediaKind.movie : MediaKind.show, num);
  }

  String _episodeId(String titleId, int season, int number) =>
      '$titleId:$season:$number';

  // ---- mapping -------------------------------------------------------------
  MediaTitle _fromSearch(Map<String, dynamic> j) {
    final id = (j['objectID'] ?? j['id'] ?? '') as String;
    final kind = id.startsWith('movie') ? MediaKind.movie : MediaKind.show;
    return MediaTitle(
      id: id,
      kind: kind,
      name: (j['translations'] as Map<String, dynamic>?)?['eng'] as String? ??
          j['name'] as String? ??
          'Unknown',
      poster: TvdbApi.absoluteImage(j['image_url'] as String?),
      yearLine: (j['year'] ?? j['first_air_time'] ?? '') as String,
      metaLine: [
        if (j['year'] != null) j['year'] as String,
        if (j['network'] != null) j['network'] as String,
      ].join(' • '),
      genres: (j['genres'] as List? ?? const []).cast<String>(),
      synopsis: ((j['overviews'] as Map<String, dynamic>?)?['eng'] ??
          j['overview']) as String?,
      addedByCount: null,
    );
  }

  MediaTitle _fromFilter(Map<String, dynamic> j, MediaKind kind) {
    final id = '${kind == MediaKind.movie ? 'movie' : 'series'}-${j['id']}';
    return MediaTitle(
      id: id,
      kind: kind,
      name: j['name'] as String? ?? 'Unknown',
      poster: TvdbApi.absoluteImage(j['image'] as String?),
      yearLine: (j['firstAired'] as String? ?? '').split('-').first,
      metaLine: (j['status'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    );
  }

  Future<MediaTitle> _loadSeries(int num) async {
    final id = 'series-$num';
    final ext = await tvdb.seriesExtended(num);
    final eps = await tvdb.seriesEpisodes(num);

    final seasonsMap = <int, List<EpisodeRef>>{};
    for (final e in eps) {
      final s = e['seasonNumber'] as int? ?? 0;
      final n = e['number'] as int? ?? 0;
      if (s == 0) continue; // specials folded out of the default view
      final airRaw = e['aired'] as String?;
      seasonsMap.putIfAbsent(s, () => []).add(EpisodeRef(
            id: _episodeId(id, s, n),
            season: s,
            number: n,
            absoluteNumber: e['absoluteNumber'] as int?,
            title: e['name'] as String? ?? 'Episode $n',
            still: TvdbApi.absoluteImage(e['image'] as String?),
            airDate: airRaw == null ? null : DateTime.tryParse(airRaw),
            synopsis: e['overview'] as String?,
          ));
    }
    final seasons = seasonsMap.entries
        .map((e) => SeasonRef(
            number: e.key, label: 'Season ${e.key}', episodes: e.value))
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));

    final characters = (ext['characters'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((c) => c['peopleType'] == 'Actor')
        .take(12)
        .map((c) => CastMember(
              name: c['personName'] as String? ?? '',
              role: c['name'] as String? ?? '',
              photo: TvdbApi.absoluteImage(c['image'] as String?),
            ))
        .toList();

    final status =
        (ext['status'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    final network = ((ext['latestNetwork'] ??
            ext['originalNetwork']) as Map<String, dynamic>?)?['name']
        as String?;
    final year = (ext['firstAired'] as String? ?? '').split('-').first;
    final lastYear = (ext['lastAired'] as String? ?? '').split('-').first;

    final title = MediaTitle(
      id: id,
      kind: MediaKind.show,
      name: _englishName(ext),
      poster: TvdbApi.absoluteImage(ext['image'] as String?),
      banner: _firstArtwork(ext, 3) ?? TvdbApi.absoluteImage(ext['image'] as String?),
      yearLine: lastYear.isNotEmpty && lastYear != year
          ? '$year - $lastYear'
          : year,
      metaLine: [
        '${seasons.length} season${seasons.length == 1 ? '' : 's'}',
        if (status.isNotEmpty) status,
        if (network != null) network,
      ].join(' • '),
      genres: (ext['genres'] as List? ?? const [])
          .map((g) => (g as Map<String, dynamic>)['name'] as String? ?? '')
          .where((g) => g.isNotEmpty)
          .toList(),
      synopsis: _englishOverview(ext),
      scorePercent: null,
      starRating: null,
      cast: characters,
      seasons: seasons,
    );
    _cache[id] = title;
    return title;
  }

  String _englishName(Map<String, dynamic> ext) {
    final translations =
        ext['translations'] as Map<String, dynamic>? ?? const {};
    final names = (translations['nameTranslations'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    for (final t in names) {
      if (t['language'] == 'eng' && t['name'] != null) {
        return t['name'] as String;
      }
    }
    final aliases = (ext['aliases'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    for (final a in aliases) {
      if (a['language'] == 'eng') return a['name'] as String;
    }
    return ext['name'] as String? ?? 'Unknown';
  }

  String? _englishOverview(Map<String, dynamic> ext) {
    final translations =
        ext['translations'] as Map<String, dynamic>? ?? const {};
    final overviews =
        (translations['overviewTranslations'] as List? ?? const [])
            .cast<Map<String, dynamic>>();
    for (final t in overviews) {
      if (t['language'] == 'eng' && t['overview'] != null) {
        return t['overview'] as String;
      }
    }
    return ext['overview'] as String?;
  }

  String? _firstArtwork(Map<String, dynamic> ext, int type) {
    final artworks =
        (ext['artworks'] as List? ?? const []).cast<Map<String, dynamic>>();
    for (final a in artworks) {
      if (a['type'] == type) {
        return TvdbApi.absoluteImage(a['image'] as String?);
      }
    }
    return null;
  }

  Future<MediaTitle> _loadMovie(int num) async {
    final id = 'movie-$num';
    final ext = await tvdb.movieExtended(num);
    final runtime = ext['runtime'] as int? ?? 0;
    final title = MediaTitle(
      id: id,
      kind: MediaKind.movie,
      name: ext['name'] as String? ?? 'Unknown',
      poster: TvdbApi.absoluteImage(ext['image'] as String?),
      banner: _firstArtwork(ext, 15) ??
          TvdbApi.absoluteImage(ext['image'] as String?),
      yearLine: (ext['year'] ?? '') as String,
      metaLine: [
        if (runtime > 0) '${runtime ~/ 60}h ${runtime % 60}m',
        (ext['status'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      ].where((s) => s.isNotEmpty).join(' • '),
      genres: (ext['genres'] as List? ?? const [])
          .map((g) => (g as Map<String, dynamic>)['name'] as String? ?? '')
          .where((g) => g.isNotEmpty)
          .toList(),
      synopsis: ((ext['translations'] as Map<String, dynamic>?)?[
                  'overviewTranslations'] as List?)
              ?.cast<Map<String, dynamic>>()
              .where((t) => t['language'] == 'eng')
              .map((t) => t['overview'] as String?)
              .firstOrNull ??
          ext['overview'] as String?,
      cast: (ext['characters'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((c) => c['peopleType'] == 'Actor')
          .take(12)
          .map((c) => CastMember(
                name: c['personName'] as String? ?? '',
                role: c['name'] as String? ?? '',
                photo: TvdbApi.absoluteImage(c['image'] as String?),
              ))
          .toList(),
    );
    _cache[id] = title;
    return title;
  }

  // ---- AniList fallback ----------------------------------------------------

  String _aniId(AniListMedia m) =>
      '${m.isMovie ? 'movie' : 'series'}-al-${m.id}';

  /// List-level mapping (search results, trending rails).
  MediaTitle _fromAniList(AniListMedia m) {
    return MediaTitle(
      id: _aniId(m),
      kind: m.isMovie ? MediaKind.movie : MediaKind.show,
      name: m.name,
      poster: m.poster,
      banner: m.banner,
      yearLine: m.startDate == null ? '' : '${m.startDate!.year}',
      metaLine: [
        if (m.startDate != null) '${m.startDate!.year}',
        if (m.format != null) m.format!,
      ].join(' • '),
      genres: m.genres,
      synopsis: m.description,
      scorePercent: m.score?.toDouble(),
    );
  }

  /// Detail-level load: synthesizes a single-season episode list from the
  /// AniList episode count / airing schedule so tracking, swiping and
  /// Upcoming all work without TVDB.
  Future<MediaTitle> _loadAniListTitle(MediaKind kind, int num) async {
    final id = '${kind == MediaKind.movie ? 'movie' : 'series'}-al-$num';
    final m = await anilist.mediaById(num);
    if (m == null) throw TvdbException('AniList title $num not found');

    final now = DateTime.now();
    List<SeasonRef> seasons = const [];
    if (kind == MediaKind.show) {
      var aired = m.episodes ?? m.streamingEpisodes.length;
      if (m.status == 'RELEASING' && m.nextEpisodeNumber != null) {
        aired = m.nextEpisodeNumber! - 1;
      }
      if (aired <= 0 && m.episodes == null) aired = 12;
      final upcoming = m.status == 'RELEASING' && m.nextEpisodeNumber != null;
      final total = upcoming ? aired + 1 : (m.episodes ?? aired);

      final start = m.startDate ??
          now.subtract(Duration(days: 7 * (aired + 1)));
      final eps = <EpisodeRef>[];
      for (var n = 1; n <= total; n++) {
        final stream =
            n <= m.streamingEpisodes.length ? m.streamingEpisodes[n - 1] : null;
        DateTime airDate;
        if (upcoming && n == total) {
          airDate = m.nextEpisodeAiring ?? now.add(const Duration(days: 7));
        } else {
          airDate = start.add(Duration(days: 7 * (n - 1)));
          // Aired episodes must sort before now even when the weekly
          // cadence guess overshoots the calendar.
          if (!airDate.isBefore(now)) {
            airDate = now.subtract(Duration(hours: total - n + 1));
          }
        }
        eps.add(EpisodeRef(
          id: '$id:1:$n',
          season: 1,
          number: n,
          title: stream != null && stream.title.isNotEmpty
              ? stream.title
              : 'Episode $n',
          still: stream?.thumbnail,
          airDate: airDate,
        ));
      }
      seasons = [SeasonRef(number: 1, label: 'Season 1', episodes: eps)];
    }

    final title = MediaTitle(
      id: id,
      kind: kind,
      name: m.name,
      poster: m.poster,
      banner: m.banner ?? m.poster,
      yearLine: m.startDate == null ? '' : '${m.startDate!.year}',
      metaLine: [
        if (kind == MediaKind.show) '1 season',
        if (m.status != null) _titleCase(m.status!),
        if (m.score != null) '${m.score}%',
      ].join(' • '),
      genres: m.genres,
      synopsis: m.description,
      scorePercent: m.score?.toDouble(),
      seasons: seasons,
    );
    _cache[id] = title;
    return title;
  }

  static String _titleCase(String s) => s.isEmpty
      ? s
      : s[0].toUpperCase() + s.substring(1).toLowerCase().replaceAll('_', ' ');

  // ---- ContentRepository ---------------------------------------------------
  @override
  Future<MediaTitle> titleById(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final ani = parseAniListId(id);
    if (ani != null) return _loadAniListTitle(ani.$1, ani.$2);
    final parsed = parseId(id);
    if (parsed == null) throw TvdbException('bad id: $id');
    return parsed.$1 == MediaKind.movie
        ? _loadMovie(parsed.$2)
        : _loadSeries(parsed.$2);
  }

  @override
  Future<List<WatchlistEntry>> showWatchlist() async {
    final ids = [
      ...appState.idsWithStatus(TrackStatus.watching),
      ...appState.idsWithStatus(TrackStatus.planToWatch),
    ].where((id) => id.startsWith('series')).toList();
    final entries = <WatchlistEntry>[];
    for (final id in ids) {
      try {
        final t = await titleById(id);
        EpisodeRef? upNext;
        var unwatchedAhead = 0;
        for (final s in t.seasons) {
          for (final e in s.episodes) {
            final aired = e.airDate != null &&
                e.airDate!.isBefore(DateTime.now());
            if (!aired) continue;
            if (!appState.isWatched(e.id)) {
              upNext ??= e;
              unwatchedAhead++;
            }
          }
        }
        entries.add(WatchlistEntry(
            title: t,
            upNext: upNext,
            unwatchedAhead: upNext == null ? 0 : unwatchedAhead - 1));
      } catch (_) {
        // one broken title must not sink the list
      }
    }
    return entries;
  }

  @override
  Future<List<UpcomingItem>> showUpcoming() async {
    final now = DateTime.now();
    final items = <UpcomingItem>[];
    for (final id in appState.trackedIds.where((i) => i.startsWith('series'))) {
      try {
        final t = await titleById(id);
        for (final s in t.seasons) {
          for (final e in s.episodes) {
            if (e.airDate == null || e.airDate!.isBefore(now)) continue;
            final days = e.airDate!.difference(now).inDays;
            items.add(UpcomingItem(
              titleId: id,
              showName: t.name,
              poster: t.poster ?? '',
              episode: e,
              daysUntil: days,
              airTime: days == 0 ? 'Today' : null,
              isLatest: true,
            ));
          }
        }
      } catch (_) {}
    }
    items.sort((a, b) => (a.daysUntil ?? 0).compareTo(b.daysUntil ?? 0));
    return items.take(30).toList();
  }

  @override
  Future<List<MediaTitle>> movieWatchlist() async {
    final ids = appState.trackedIds.where((i) => i.startsWith('movie'));
    final out = <MediaTitle>[];
    for (final id in ids) {
      try {
        out.add(await titleById(id));
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<List<MediaTitle>> trending(MediaKind kind) async {
    if (!tvdb.isConfigured) {
      final anime = await anilist.trendingAnime(
          perPage: 15, format: kind == MediaKind.movie ? 'MOVIE' : 'TV');
      return anime.map(_fromAniList).toList();
    }
    final rows = kind == MediaKind.movie
        ? await tvdb.trendingMovies()
        : await tvdb.trendingSeries();
    return rows.take(15).map((j) => _fromFilter(j, kind)).toList();
  }

  @override
  Future<List<MediaTitle>> topForYou() async {
    // AniList wiring: trending anime as the personalized rail.
    final anime = await anilist.trendingAnime();
    return anime.map(_fromAniList).toList();
  }

  @override
  Future<List<MediaTitle>> search(String query, MediaKind? kind) async {
    if (query.trim().isEmpty) {
      return trending(kind ?? MediaKind.show);
    }
    if (!tvdb.isConfigured) {
      final anime = await anilist.searchAnime(query,
          format: kind == null
              ? null
              : (kind == MediaKind.movie ? 'MOVIE' : 'TV'));
      return anime.map(_fromAniList).toList();
    }
    final rows = await tvdb.search(query,
        type: kind == null
            ? null
            : (kind == MediaKind.movie ? 'movie' : 'series'));
    return rows
        .where((j) {
          final id = (j['objectID'] ?? '') as String;
          return id.startsWith('series') || id.startsWith('movie');
        })
        .map(_fromSearch)
        .toList();
  }

  /// Artwork lists for the poster/banner picker. TVDB artwork types:
  /// 2 = series poster, 3 = series background, 14 = movie poster,
  /// 15 = movie background.
  @override
  Future<List<String>> artworkUrls(String titleId,
      {required bool posters}) async {
    final ani = parseAniListId(titleId);
    if (ani != null) {
      // AniList exposes one cover + one banner; no picker gallery.
      final t = await titleById(titleId);
      return [
        if (posters && t.poster != null) t.poster!,
        if (!posters && t.banner != null) t.banner!,
      ];
    }
    final parsed = parseId(titleId);
    if (parsed == null) return const [];
    if (parsed.$1 == MediaKind.movie) {
      final ext = await tvdb.movieExtended(parsed.$2);
      final artworks =
          (ext['artworks'] as List? ?? const []).cast<Map<String, dynamic>>();
      final type = posters ? 14 : 15;
      return artworks
          .where((a) => a['type'] == type)
          .map((a) => TvdbApi.absoluteImage(a['image'] as String?))
          .whereType<String>()
          .take(24)
          .toList();
    }
    final artworks = await tvdb.seriesArtworks(parsed.$2);
    final type = posters ? 2 : 3;
    return artworks
        .where((a) => a['type'] == type)
        .map((a) => TvdbApi.absoluteImage(a['image'] as String?))
        .whereType<String>()
        .take(24)
        .toList();
  }

  final Map<String, BrandArt> _brandCache = {};

  /// Clear-logo, background and banner for the VHS shelf, by TVDB v4
  /// artwork type (`/artwork/types`): series 23 / 3 / 1, movies 25 / 15 /
  /// 16. AniList titles have no logo; their banner image serves as both
  /// background and banner.
  @override
  Future<BrandArt> brandArt(String titleId) async {
    final cached = _brandCache[titleId];
    if (cached != null) return cached;
    BrandArt art;
    try {
      final ani = parseAniListId(titleId);
      final parsed = parseId(titleId);
      if (ani != null || parsed == null || !tvdb.isConfigured) {
        final t = await titleById(titleId);
        art = BrandArt(background: t.banner ?? t.poster, banner: t.banner);
      } else if (parsed.$1 == MediaKind.movie) {
        final ext = await tvdb.movieExtended(parsed.$2);
        final artworks = (ext['artworks'] as List? ?? const [])
            .cast<Map<String, dynamic>>();
        String? byType(int type) => TvdbApi.absoluteImage(artworks
            .firstWhere((a) => a['type'] == type,
                orElse: () => const {})['image'] as String?);
        art = BrandArt(
            clearLogo: byType(25), background: byType(15), banner: byType(16));
      } else {
        final artworks = await tvdb.seriesArtworks(parsed.$2);
        String? byType(int type) => TvdbApi.absoluteImage(artworks
            .firstWhere((a) => a['type'] == type,
                orElse: () => const {})['image'] as String?);
        art = BrandArt(
            clearLogo: byType(23), background: byType(3), banner: byType(1));
      }
      if (art.background == null) {
        final t = await titleById(titleId);
        art = BrandArt(
            clearLogo: art.clearLogo,
            background: t.banner ?? t.poster,
            banner: art.banner);
      }
    } catch (_) {
      art = const BrandArt();
    }
    _brandCache[titleId] = art;
    return art;
  }

  // ---- Social/profile: account-local, no backend yet ----------------------
  @override
  Future<List<Comment>> comments(String titleId) async => const [
        Comment(
            user: 'NextCue',
            date: 'today',
            body:
                'Comments live here once the community backend is connected.',
            likes: 0,
            replies: 0),
      ];

  @override
  Future<List<GroupInfo>> groups() async => const [];

  @override
  Future<GroupInfo> groupById(String id) async =>
      const GroupInfo(id: 'x', name: 'Group');

  @override
  Future<List<Person>> following() async => const [];

  @override
  Future<UserProfile> profile() async => const UserProfile(name: '');

  @override
  Future<List<StatRow>> statTable(String key) async => const [];
}
