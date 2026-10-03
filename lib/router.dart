import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'services/auth_service.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell_scaffold.dart';
import 'screens/shows_screen.dart';
import 'screens/movies_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/decide_screen.dart';
import 'screens/search_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/profile_edit_screen.dart';
import 'screens/following_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/title_detail_screen.dart';
import 'screens/episode_detail_screen.dart';
import 'screens/comments_screen.dart';
import 'screens/collection_screen.dart';
import 'models/models.dart';

/// One route per recon sitemap entry, matching the source URL shapes.
/// First launch shows /onboarding; unauthenticated sessions are then
/// redirected to /login.
GoRouter buildRouter(AuthController auth,
    {ValueNotifier<bool>? onboarded}) {
  final shellKey = GlobalKey<NavigatorState>();
  final seen = onboarded ?? ValueNotifier(true);

  return GoRouter(
    initialLocation: '/shows/watchlist',
    refreshListenable: Listenable.merge([auth, seen]),
    redirect: (context, state) {
      final onOnboarding = state.uri.path == '/onboarding';
      if (!seen.value) return onOnboarding ? null : '/onboarding';
      if (onOnboarding) {
        return auth.loggedIn ? '/shows/watchlist' : '/login';
      }
      final onLogin = state.uri.path == '/login';
      if (!auth.loggedIn) return onLogin ? null : '/login';
      if (onLogin) return '/shows/watchlist';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (c, s) => OnboardingScreen(
          onFinish: () async {
            final p = await SharedPreferences.getInstance();
            await p.setBool('nextcue.onboarded', true);
            seen.value = true;
          },
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (c, s) => const AuthScreen(),
      ),
      ShellRoute(
        navigatorKey: shellKey,
        builder: (context, state, child) =>
            ShellScaffold(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/shows/:tab',
            builder: (c, s) =>
                ShowsScreen(tab: s.pathParameters['tab'] ?? 'watchlist'),
          ),
          GoRoute(
            path: '/movies/:tab',
            builder: (c, s) =>
                MoviesScreen(tab: s.pathParameters['tab'] ?? 'watchlist'),
          ),
          GoRoute(
            path: '/explore/:tab',
            builder: (c, s) =>
                ExploreScreen(tab: s.pathParameters['tab'] ?? 'feed'),
          ),
          GoRoute(
            path: '/profile',
            builder: (c, s) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/search',
        builder: (c, s) => const SearchScreen(),
      ),
      GoRoute(
        path: '/decide',
        builder: (c, s) => const DecideScreen(),
      ),
      GoRoute(
        path: '/browse',
        builder: (c, s) => BrowseScreen(
          initialKind: s.uri.queryParameters['kind'] == 'movie'
              ? MediaKind.movie
              : MediaKind.show,
        ),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (c, s) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (c, s) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: '/profile/following',
        builder: (c, s) => const FollowingScreen(),
      ),
      GoRoute(
        path: '/stats',
        builder: (c, s) => const StatsScreen(),
      ),
      GoRoute(
        path: '/collection',
        builder: (c, s) => const CollectionScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (c, s) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (c, s) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/series/:id',
        builder: (c, s) => TitleDetailScreen(
          titleId: s.pathParameters['id']!,
          kind: MediaKind.show,
          initialTab: s.uri.queryParameters['tab'] ?? 'about',
        ),
      ),
      GoRoute(
        path: '/movie/:id',
        builder: (c, s) => TitleDetailScreen(
          titleId: s.pathParameters['id']!,
          kind: MediaKind.movie,
          initialTab: s.uri.queryParameters['tab'] ?? 'about',
        ),
      ),
      GoRoute(
        path: '/series/:id/episode/:eid',
        builder: (c, s) => EpisodeDetailScreen(
          titleId: s.pathParameters['id']!,
          episodeId: s.pathParameters['eid']!,
        ),
      ),
      GoRoute(
        path: '/series/:id/reviews',
        builder: (c, s) => CommentsScreen(titleId: s.pathParameters['id']!),
      ),
    ],
  );
}
