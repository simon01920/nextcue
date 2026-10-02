import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/poster.dart';
import '../widgets/title_actions.dart';

class ExploreScreen extends StatelessWidget {
  final String tab;
  const ExploreScreen({super.key, required this.tab});

  // Groups were removed from Explore — the tab set is Feed / Discover /
  // Activity only. '/explore/groups' still resolves (to Discover) so old
  // deep links and back-stack entries don't 404.
  static const _tabs = ['feed', 'discover', 'activity'];

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final raw = _tabs.indexOf(tab);
    final index = raw < 0 ? (tab == 'groups' ? 1 : 0) : raw;
    return Column(
      key: const Key('exploreScreen'),
      children: [
        const _SearchField(),
        _ChipTabs(index: index),
        Expanded(child: _body(context, repo, index)),
      ],
    );
  }

  Widget _body(BuildContext context, ContentRepository repo, int index) {
    switch (index) {
      case 1:
        return _DiscoverBody(repo: repo);
      case 2:
        return _ActivityBody(repo: repo);
      default:
        return _FeedBody(repo: repo);
    }
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: GestureDetector(
        onTap: () => context.push('/search'),
        child: Container(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          decoration: BoxDecoration(
            border:
                Border(bottom: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: AppColors.textDisabled, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Text('Search',
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textDisabled)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipTabs extends StatelessWidget {
  final int index;
  const _ChipTabs({required this.index});
  static const _labels = ['FEED', 'DISCOVER', 'ACTIVITY'];
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: _labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (c, i) {
          final active = i == index;
          return Center(
            child: GestureDetector(
              onTap: () =>
                  context.go('/explore/${_labels[i].toLowerCase()}'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: active ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(_labels[i],
                    style: AppTextStyles.captionCaps.copyWith(
                      color: active
                          ? AppColors.accentInk
                          : AppColors.textPrimary,
                    )),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeedBody extends StatelessWidget {
  final ContentRepository repo;
  const _FeedBody({required this.repo});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaTitle>>(
      future: repo.trending(MediaKind.show),
      builder: (context, snap) {
        if (!snap.hasData) return const _Spinner();
        return ListView(
          padding: EdgeInsets.only(
              bottom: AppSpacing.xl + MediaQuery.paddingOf(context).bottom),
          children: [
            for (final t in snap.data!) _FeedCard(title: t),
          ],
        );
      },
    );
  }
}

class _FeedCard extends StatelessWidget {
  final MediaTitle title;
  const _FeedCard({required this.title});
  @override
  Widget build(BuildContext context) {
    final tracked = context.watch<AppState>().statusOf(title.id) != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GestureDetector(
        onTap: () => context.push(
            '/${title.kind == MediaKind.movie ? 'movie' : 'series'}/${title.id}'),
        onLongPress: () => showTitleActions(context, title: title),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Poster(
                    radius: 0,
                    imageAsset: title.banner ?? title.poster,
                    label: title.name),
              ),
              Positioned(
                top: AppSpacing.md,
                right: AppSpacing.md,
                child: AddToListButton(title: title, tracked: tracked),
              ),
              Positioned(
                left: AppSpacing.md,
                bottom: AppSpacing.md,
                right: AppSpacing.md,
                child: Row(
                  children: [
                    const Icon(Icons.tv, color: Colors.white, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(title.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.screenTitle
                              .copyWith(fontSize: 22)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              title.synopsis ?? 'A trending title on NextCue this week.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body,
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverBody extends StatelessWidget {
  final ContentRepository repo;
  const _DiscoverBody({required this.repo});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _DecideCard(repo: repo),
        _Rail(title: 'Top shows for you', future: repo.topForYou()),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: BrandButton(
            label: 'BROWSE ALL SHOWS',
            leading: const Icon(Icons.tv, color: AppColors.accentInk, size: 20),
            onTap: () => context.push('/browse?kind=show'),
          ),
        ),
        _Rail(title: 'Trending movies', future: repo.trending(MediaKind.movie)),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: BrandButton(
            label: 'BROWSE ALL MOVIES',
            leading:
                const Icon(Icons.movie, color: AppColors.accentInk, size: 20),
            onTap: () => context.push('/browse?kind=movie'),
          ),
        ),
      ],
    );
  }
}

/// Entry point for the Decide feature (Task 3): a glass card that opens the
/// wheel / coin-flip picker. Disabled (dimmed, no tap) with fewer than 2
/// shows in the watch list.
class _DecideCard extends StatelessWidget {
  final ContentRepository repo;
  const _DecideCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    // Watching revision keeps the count fresh as shows are added/removed.
    context.watch<AppState>().revision;
    return FutureBuilder<List<WatchlistEntry>>(
      future: repo.showWatchlist(),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        final enabled = count >= 2;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: GestureDetector(
              onTap: enabled ? () => context.push('/decide') : null,
              child: GlassSurface(
                stadium: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(alpha: 0.18),
                        border: Border.all(
                            color:
                                AppColors.accent.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.casino,
                          color: AppColors.accentAlt, size: 24),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Can't pick? Decide for me",
                              style: AppTextStyles.rowTitleList),
                          const SizedBox(height: 2),
                          Text(
                            enabled
                                ? 'Spin for one of your $count shows'
                                : 'Add at least 2 shows to your watch list',
                            style: AppTextStyles.subtitle,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Rail extends StatelessWidget {
  final String title;
  final Future<List<MediaTitle>> future;
  const _Rail({required this.title, required this.future});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title,
            onMore: () => context.push(
                '/browse?kind=${title.toLowerCase().contains('movie') ? 'movie' : 'show'}')),
        SizedBox(
          height: AppLayout.railPosterH,
          child: FutureBuilder<List<MediaTitle>>(
            future: future,
            builder: (context, snap) {
              if (!snap.hasData) return const _Spinner();
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: snap.data!.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (c, i) {
                  final t = snap.data![i];
                  final tracked =
                      context.watch<AppState>().statusOf(t.id) != null;
                  return GestureDetector(
                    onTap: () => context.push(
                        '/${t.kind == MediaKind.movie ? 'movie' : 'series'}/${t.id}'),
                    onLongPress: () => showTitleActions(context, title: t),
                    child: Stack(
                      children: [
                        Poster(
                            width: AppLayout.railPosterW,
                            height: AppLayout.railPosterH,
                            imageAsset: t.poster,
                            label: t.name),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: AddToListButton(title: t, tracked: tracked),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActivityBody extends StatelessWidget {
  final ContentRepository repo;
  const _ActivityBody({required this.repo});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaTitle>>(
      future: repo.trending(MediaKind.movie),
      builder: (context, snap) {
        if (!snap.hasData) return const _Spinner();
        return ListView(
          children: [
            for (final t in snap.data!) _ActivityCard(title: t),
          ],
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final MediaTitle title;
  const _ActivityCard({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Poster(
                      radius: 0,
                      imageAsset: title.banner ?? title.poster,
                      label: title.name)),
              Positioned(
                  left: AppSpacing.md,
                  bottom: AppSpacing.md,
                  child: Row(children: [
                    const Icon(Icons.movie, color: Colors.white, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Text(title.name, style: AppTextStyles.rowTitle),
                  ])),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Align(
                    widthFactor: 0.7,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bgPrimary, width: 2),
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.sm),
                Text('Watched by +27,9 tis.', style: AppTextStyles.subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: AppColors.accent),
          ),
        ),
      );
}
