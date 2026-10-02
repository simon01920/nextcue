import '../state/app_state.dart';
import 'anilist_api.dart';

/// Demo account credentials, surfaced by the TRY THE DEMO button on the
/// auth screen so the app is explorable without registering.
const String demoEmail = 'demo@nextcue.app';
const String demoPassword = 'demo1234';
const String demoDisplayName = 'Demo';

/// Seeds the demo account once from AniList trending: two shows mid-watch
/// (Up Next rows to swipe), five planned (enough for the Decide wheel),
/// four finished (the DVD shelf) and two movies. Safe to call on every
/// demo login — a per-account flag makes it a no-op after the first run.
Future<void> seedDemoContent(AppState state, AniListApi anilist) async {
  if (state.uid == 'anon') return;
  if (!await state.claimOnce('demoContent')) return;
  try {
    final shows = await anilist.trendingAnime(perPage: 12, format: 'TV');
    for (var i = 0; i < shows.length; i++) {
      final id = 'series-al-${shows[i].id}';
      if (i < 2) {
        state.setStatus(id, TrackStatus.watching);
        for (var e = 1; e <= 3; e++) {
          state.setWatched('$id:1:$e', true);
        }
      } else if (i < 7) {
        state.setStatus(id, TrackStatus.planToWatch);
      } else if (i < 11) {
        state.setStatus(id, TrackStatus.completed);
      }
    }
    final movies = await anilist.trendingAnime(perPage: 2, format: 'MOVIE');
    for (var i = 0; i < movies.length; i++) {
      state.setStatus('movie-al-${movies[i].id}',
          i == 0 ? TrackStatus.planToWatch : TrackStatus.completed);
    }
  } catch (_) {
    // Offline first run: the demo account simply starts empty.
  }
}
