import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/poster.dart';
import '../widgets/title_actions.dart';
import '../widgets/top_tabs.dart';
import '../widgets/watch_history.dart';

class MoviesScreen extends StatefulWidget {
  final String tab;
  const MoviesScreen({super.key, required this.tab});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  bool _grid = true;
  int _prevTab = 0;
  int get _tabIndex => widget.tab == 'upcoming' ? 1 : 0;

  @override
  void didUpdateWidget(MoviesScreen old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      _prevTab = old.tab == 'upcoming' ? 1 : 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final body = _tabIndex == 1
        ? EmptyState(
            title: 'Your upcoming list is empty!',
            subtitle: 'Add movies you want to watch.',
            ctaLabel: 'BROWSE ALL MOVIES',
            onCta: () => context.go('/explore/discover'),
          )
        : FutureBuilder<List<MediaTitle>>(
            future: repo.movieWatchlist(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: AppColors.accent),
                  ),
                );
              }
              final movies = snap.data!;
              return _grid
                  ? _MovieGrid(movies: movies)
                  : _MovieList(movies: movies);
            },
          );
    return Column(
      key: const Key('moviesScreen'),
      children: [
        TopTabs(
          labels: const ['WATCH LIST', 'UPCOMING'],
          index: _tabIndex,
          onChanged: (i) =>
              context.go('/movies/${i == 0 ? 'watchlist' : 'upcoming'}'),
        ),
        if (_tabIndex == 0)
          Padding(
            padding:
                const EdgeInsets.only(right: AppSpacing.md, top: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(_grid ? Icons.view_agenda_outlined : Icons.grid_view,
                    size: 22, color: AppColors.textPrimary),
                onPressed: () => setState(() => _grid = !_grid),
              ),
            ),
          ),
        Expanded(
          // Same slide-between-tabs treatment as the Shows screen.
          child: AnimatedSwitcher(
            duration: AppMotion.slide,
            switchInCurve: AppMotion.glide,
            switchOutCurve: AppMotion.glide,
            transitionBuilder: (child, anim) {
              final incoming =
                  (child.key as ValueKey?)?.value == _tabIndex;
              final dir = _tabIndex >= _prevTab ? 1.0 : -1.0;
              final from = incoming ? Offset(dir, 0) : Offset(-dir, 0);
              return ClipRect(
                child: SlideTransition(
                  position: Tween<Offset>(begin: from, end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(key: ValueKey(_tabIndex), child: body),
          ),
        ),
      ],
    );
  }
}

class _MovieGrid extends StatelessWidget {
  final List<MediaTitle> movies;
  const _MovieGrid({required this.movies});
  @override
  Widget build(BuildContext context) {
    final cols = AppBreakpoints.gridColumns(MediaQuery.sizeOf(context).width);
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SectionChip('WATCH NEXT')),
        SliverPadding(
          padding: EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: MediaQuery.paddingOf(context).bottom),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: AppLayout.gridGap,
              mainAxisSpacing: AppLayout.gridGap,
            ),
            delegate: SliverChildBuilderDelegate(
              (c, i) {
                final m = movies[i];
                final appState = context.watch<AppState>();
                final watched =
                    appState.statusOf(m.id) == TrackStatus.completed;
                return GestureDetector(
                  onTap: () => context.push('/movie/${m.id}'),
                  onLongPress: () => showTitleActions(context, title: m),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Poster(
                        imageAsset:
                            appState.posterOverride(m.id) ?? m.poster,
                        label: m.name,
                      ),
                      if (watched)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.check,
                                size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                );
              },
              childCount: movies.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _MovieList extends StatelessWidget {
  final List<MediaTitle> movies;
  const _MovieList({required this.movies});
  @override
  Widget build(BuildContext context) {
    // Same pull-down-for-history gesture as the Shows watch list.
    return OverscrollReveal(
      onReveal: () => showWatchHistory(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        children: [
          const SectionChip('WATCH NEXT'),
          for (final m in movies) _MovieRow(movie: m),
        ],
      ),
    );
  }
}

class _MovieRow extends StatelessWidget {
  final MediaTitle movie;
  const _MovieRow({required this.movie});
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // A movie has no episodes, so "watched" maps to the completed status —
    // the same signal the profile counts under "Movies watched".
    final watched = appState.statusOf(movie.id) == TrackStatus.completed;
    return InkWell(
      onTap: () => context.push('/movie/${movie.id}'),
      onLongPress: () => showTitleActions(context, title: movie),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        child: Row(
          children: [
            Poster(
                width: 88,
                height: 88,
                imageAsset: appState.posterOverride(movie.id) ?? movie.poster,
                label: movie.name),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(movie.name, style: AppTextStyles.rowTitleList),
                  const SizedBox(height: AppSpacing.xs),
                  Text(movie.metaLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.subtitle),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            WatchCheck(
              watched: watched,
              onTap: () {
                HapticFeedback.selectionClick();
                context.read<AppState>().setStatus(movie.id,
                    watched ? TrackStatus.planToWatch : TrackStatus.completed);
              },
            ),
          ],
        ),
      ),
    );
  }
}
