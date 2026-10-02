import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/poster.dart';
import '../widgets/vhs_shelf.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final appState = context.watch<AppState>();
    final account = auth.account;
    final seeded = auth.isSeededProfile;

    // Real numbers derived from the account's tracked state (est. 24 min
    // per episode, 110 min per movie).
    final watchedEpisodes = appState.watchedEpisodeTotal;
    final moviesWatched = appState
        .idsWithStatus(TrackStatus.completed)
        .where((i) => i.startsWith('movie'))
        .length;
    final stats = <StatCard>[
      StatCard(label: 'TV time', units: _timeUnits(watchedEpisodes * 24)),
      StatCard(label: 'Episodes watched', value: '$watchedEpisodes'),
      StatCard(label: 'Movie time', units: _timeUnits(moviesWatched * 110)),
      StatCard(label: 'Movies watched', value: '$moviesWatched'),
    ];

    final favourites = appState.favoriteIds;
    final trackedShows =
        appState.trackedIds.where((i) => i.startsWith('series')).toList();
    final trackedMovies =
        appState.trackedIds.where((i) => i.startsWith('movie')).toList();

    return ListView(
      key: const Key('profileScreen'),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      children: [
        _Header(name: account?.displayName ?? 'Guest'),
        _CountsBar(
          following: seeded ? 11 : 0,
          followers: seeded ? 18 : 0,
          comments: seeded ? 39 : 0,
        ),
        // VHS favourites shelf — favourites live here now.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.lg, AppSpacing.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Favourites shelf',
                  style: AppTextStyles.sectionHeader),
              const SizedBox(height: 2),
              Text(
                  '${favourites.length}/${AppState.favoriteLimitFree} tapes',
                  style: AppTextStyles.subtitle),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        VhsShelf(ids: favourites),
        SectionHeader('Stats', onMore: () => context.push('/stats')),
        _StatCards(cards: stats),
        SectionHeader('Shows', onMore: () => context.go('/shows/watchlist')),
        _IdsRail(ids: trackedShows, emptyHint: 'Track shows to see them here'),
        SectionHeader('Movies', onMore: () => context.go('/movies/watchlist')),
        _IdsRail(
            ids: trackedMovies, emptyHint: 'Track movies to see them here'),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  const _Header({required this.name});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          const Positioned.fill(child: Poster(radius: 0)),
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.md,
            child: GestureDetector(
              onTap: () => context.push('/notifications'),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.notifications,
                    color: AppColors.accentInk, size: 22),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.md,
            child: GestureDetector(
              onTap: () => _menu(context),
              child:
                  const Icon(Icons.more_horiz, color: Colors.white, size: 26),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            bottom: AppSpacing.md,
            right: AppSpacing.md,
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                        radius: 32, backgroundColor: AppColors.surface),
                    const Positioned(
                      right: -2,
                      bottom: -2,
                      child: BingelyMark(size: 20),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppTextStyles.screenTitle),
                      const SizedBox(height: AppSpacing.xs),
                      GestureDetector(
                        onTap: () => context.push('/profile/edit'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.textPrimary),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text('EDIT',
                              style: AppTextStyles.captionCaps
                                  .copyWith(color: AppColors.textPrimary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _menu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuTile(
                Icons.settings, 'Settings', () => context.push('/settings')),
            _MenuTile(Icons.ios_share, 'Share', () {
              Clipboard.setData(
                  const ClipboardData(text: 'Track shows with me on NextCue!'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  duration: Duration(seconds: 2),
                  content: Text('Invite copied to clipboard')));
            }),
            _MenuTile(Icons.help_outline, 'Help center', () {
              showDialog<void>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Help center'),
                  content: const Text(
                    '• Tap the check next to an episode to mark it watched.\n'
                    '• Long-press any show or movie for quick actions.\n'
                    '• Pull down on your watch list to see (and undo) your '
                    'watch history.\n'
                    '• Use the + button anywhere in Explore to add a title '
                    'to Plan to watch.\n\n'
                    'Metadata provided by TheTVDB.',
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d),
                        child: const Text('GOT IT')),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuTile(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(label, style: AppTextStyles.body),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}

class _CountsBar extends StatelessWidget {
  final int following;
  final int followers;
  final int comments;
  const _CountsBar(
      {required this.following,
      required this.followers,
      required this.comments});
  @override
  Widget build(BuildContext context) {
    Widget cell(String value, String label, VoidCallback? onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                children: [
                  Text(value,
                      style:
                          AppTextStyles.rowTitleList.copyWith(fontSize: 20)),
                  Text(label, style: AppTextStyles.subtitle),
                ],
              ),
            ),
          ),
        );
    return Row(
      children: [
        cell('$following', 'following',
            () => context.push('/profile/following')),
        _sep(),
        cell('$followers', 'followers',
            () => context.push('/profile/following')),
        _sep(),
        // Plain stat — there is no per-user comment feed yet, so it must
        // not look like a button that does nothing.
        cell('$comments', 'comments', null),
      ],
    );
  }

  Widget _sep() => Container(width: 1, height: 40, color: AppColors.divider);
}

/// Months / days / hours breakdown of a minute total.
List<StatUnit> _timeUnits(int minutes) {
  final months = minutes ~/ (60 * 24 * 30);
  final days = (minutes ~/ (60 * 24)) % 30;
  final hours = (minutes ~/ 60) % 24;
  return [
    StatUnit('$months', 'MONTHS'),
    StatUnit('$days', 'DAYS'),
    StatUnit('$hours', 'HOURS'),
  ];
}

class _StatCards extends StatelessWidget {
  final List<StatCard> cards;
  const _StatCards({required this.cards});
  @override
  Widget build(BuildContext context) {
    // 2x2 on phones, one row on wide layouts — the 4-across row overflowed
    // the multi-unit time cards at phone widths.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, box) {
          final cols = box.maxWidth < 560 ? 2 : 4;
          final w =
              (box.maxWidth - AppSpacing.sm * (cols - 1)) / cols;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final c in cards)
                SizedBox(width: w, child: _StatCardTile(card: c)),
            ],
          );
        },
      ),
    );
  }
}

class _StatCardTile extends StatelessWidget {
  final StatCard card;
  const _StatCardTile({required this.card});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(card.label,
              textAlign: TextAlign.center,
              style: AppTextStyles.subtitle
                  .copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          if (card.units.isNotEmpty)
            // FittedBox guards against overflow on narrow tiles.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final u in card.units)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        children: [
                          Text(u.number,
                              style: AppTextStyles.rowTitle
                                  .copyWith(fontSize: 20)),
                          Text(u.unit, style: AppTextStyles.microCaps),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else
            Text(card.value,
                style: AppTextStyles.sectionHeader.copyWith(fontSize: 24)),
        ],
      ),
    );
  }
}

/// Horizontal poster rail resolved from a list of tracked/favorite title ids.
class _IdsRail extends StatelessWidget {
  final List<String> ids;
  final String emptyHint;
  const _IdsRail({required this.ids, required this.emptyHint});
  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Text(emptyHint, style: AppTextStyles.subtitle),
      );
    }
    final repo = context.read<ContentRepository>();
    final appState = context.read<AppState>();
    return SizedBox(
      height: AppLayout.railPosterH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: ids.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (c, i) => FutureBuilder<MediaTitle>(
          future: repo.titleById(ids[i]),
          builder: (context, snap) {
            final t = snap.data;
            return GestureDetector(
              onTap: t == null
                  ? null
                  : () => context.push(
                      '/${t.kind == MediaKind.movie ? 'movie' : 'series'}/${t.id}'),
              child: Poster(
                width: AppLayout.railPosterW,
                height: AppLayout.railPosterH,
                imageAsset: t == null
                    ? null
                    : (appState.posterOverride(t.id) ?? t.poster),
                label: t?.name,
              ),
            );
          },
        ),
      ),
    );
  }
}
