import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/poster.dart';
import '../widgets/top_tabs.dart';

class TitleDetailScreen extends StatefulWidget {
  final String titleId;
  final MediaKind kind;
  final String initialTab;
  const TitleDetailScreen({
    super.key,
    required this.titleId,
    required this.kind,
    this.initialTab = 'about',
  });

  @override
  State<TitleDetailScreen> createState() => _TitleDetailScreenState();
}

class _TitleDetailScreenState extends State<TitleDetailScreen> {
  late int _tab = widget.initialTab == 'episodes' ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    return Scaffold(
      body: ContentColumn(
        child: FutureBuilder<MediaTitle>(
          future: repo.titleById(widget.titleId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent));
            }
            final title = snap.data!;
            final tabs = title.isShow
                ? const ['ABOUT', 'EPISODES']
                : const ['ABOUT', 'MORE'];
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Banner(title: title)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsHeader(
                    tabs: tabs,
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ),
                if (_tab == 0)
                  _AboutTab(title: title, repo: repo)
                else if (title.isShow)
                  _EpisodesTab(title: title)
                else
                  SliverToBoxAdapter(
                      child: _MoreTab(title: title)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final MediaTitle title;
  const _Banner({required this.title});
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return SizedBox(
      height: AppLayout.bannerExpanded,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Poster(
              radius: 0,
              imageAsset:
                  appState.bannerOverride(title.id) ?? title.banner,
              label: title.name),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, AppColors.bannerScrim],
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.xs,
            child: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.xs,
            child: IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              onPressed: () => _overflow(context, appState),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            bottom: AppSpacing.md,
            right: AppSpacing.md,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.name,
                          style: AppTextStyles.screenTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      Text(title.metaLine, style: AppTextStyles.subtitle),
                    ],
                  ),
                ),
                if (title.scorePercent != null)
                  Row(
                    children: [
                      const _TLogo(),
                      const SizedBox(width: AppSpacing.xs),
                      Text('${title.scorePercent!.toInt()}%',
                          style: AppTextStyles.rowTitleList
                              .copyWith(color: AppColors.accent)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(TrackStatus? s) => switch (s) {
        TrackStatus.watching => 'Watching',
        TrackStatus.planToWatch => 'Watch later',
        TrackStatus.stopped => 'Stopped',
        TrackStatus.completed => 'Completed',
        null => 'Not added',
      };

  void _overflow(BuildContext context, AppState appState) {
    final status = appState.statusOf(title.id);
    final fav = appState.isFavorite(title.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  Text(_statusLabel(status),
                      style: AppTextStyles.rowTitleList),
                  const SizedBox(height: AppSpacing.xs),
                  Container(height: 3, width: 72, color: AppColors.accent),
                ],
              ),
            ),
            if (status != TrackStatus.watching)
              _sheetItem(c, Icons.play_circle_outline, 'Start watching',
                  () => appState.setStatus(title.id, TrackStatus.watching)),
            _sheetItem(c, Icons.edit, 'Customize', () => _customize(context)),
            _sheetItem(
                c,
                fav ? Icons.favorite : Icons.favorite_border,
                fav ? 'Take off the shelf' : 'Add to favourites shelf',
                () {
              if (!appState.toggleFavorite(title.id)) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: AppColors.surfaceElevated,
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    'Shelf full — ${AppState.favoriteLimitFree} tapes on '
                    'the free shelf. Take one off first.',
                    style: AppTextStyles.body,
                  ),
                ));
              }
            }),
            _sheetItem(c, Icons.schedule, 'Watch later',
                () => appState.setStatus(title.id, TrackStatus.planToWatch)),
            _sheetItem(c, Icons.cancel_outlined, 'Stop watching',
                () => appState.setStatus(title.id, TrackStatus.stopped)),
            _sheetItem(
                c,
                Icons.remove_circle_outline,
                title.isShow ? 'Remove show' : 'Remove movie',
                () => appState.setStatus(title.id, null)),
            _sheetItem(c, Icons.ios_share, 'Share', () {
              Clipboard.setData(ClipboardData(
                  text: '${title.name} — tracking it on NextCue'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  duration: Duration(seconds: 2),
                  content: Text('Copied to clipboard')));
            }),
          ],
        ),
      ),
    );
  }

  void _customize(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetItem(c, Icons.image, 'Change poster',
                () => _artworkPicker(context, poster: true)),
            _sheetItem(c, Icons.panorama, 'Change banner',
                () => _artworkPicker(context, poster: false)),
          ],
        ),
      ),
    );
  }

  void _artworkPicker(BuildContext context, {required bool poster}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _ArtworkPicker(title: title, poster: poster),
    ));
  }

  Widget _sheetItem(
      BuildContext c, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(label, style: AppTextStyles.body),
      onTap: () {
        Navigator.pop(c);
        // Defer to the next frame so a nested sheet/route (Customize →
        // pickers) opens *after* this sheet finishes popping, instead of
        // racing the dismiss animation and being swallowed.
        WidgetsBinding.instance.addPostFrameCallback((_) => onTap());
      },
    );
  }
}

class _TLogo extends StatelessWidget {
  const _TLogo();
  @override
  Widget build(BuildContext context) => const BingelyMark(size: 18);
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  _TabsHeader(
      {required this.tabs, required this.index, required this.onChanged});
  @override
  double get minExtent => AppLayout.topTabBarHeight;
  @override
  double get maxExtent => AppLayout.topTabBarHeight;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return ColoredBox(
      color: AppColors.bgPrimary,
      child: TopTabs(labels: tabs, index: index, onChanged: onChanged),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.index != index;
}

class _AboutTab extends StatelessWidget {
  final MediaTitle title;
  final ContentRepository repo;
  const _AboutTab({required this.title, required this.repo});
  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate([
        _WhereToWatch(),
        const Divider(),
        _Survey(isShow: title.isShow),
        const Divider(),
        _ShowInfo(title: title),
        if (title.cast.isNotEmpty) ...[
          const SectionHeader('Cast'),
          _CastRail(cast: title.cast),
        ],
        SectionHeader('People also watched',
            onMore: () => context.push(
                '/browse?kind=${title.isShow ? 'show' : 'movie'}')),
        _AlsoWatchedRail(repo: repo),
        _CommentsRow(title: title),
        const SizedBox(height: AppSpacing.xl),
      ]),
    );
  }
}

class _WhereToWatch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Where to watch',
                      style: AppTextStyles.sectionHeader.copyWith(fontSize: 18))),
              Icon(Icons.settings, size: 20, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Not available', style: AppTextStyles.subtitle),
        ],
      ),
    );
  }
}

class _Survey extends StatelessWidget {
  final bool isShow;
  const _Survey({required this.isShow});
  @override
  Widget build(BuildContext context) {
    final options = [
      'THE CAST',
      'THE PREMISE',
      'THE CREATORS',
      isShow ? 'THE NETWORK/PLATFORM' : 'THE STUDIO',
      'THE FRANCHISE OR UNIVERSE',
      'OTHER',
    ];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Text(
              'WHAT INTERESTS YOU MOST ABOUT THIS ${isShow ? 'SHOW' : 'MOVIE'}?',
              style: AppTextStyles.captionCaps),
          const SizedBox(height: AppSpacing.md),
          for (final o in options)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(o,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.captionCaps
                      .copyWith(color: AppColors.textPrimary)),
            ),
        ],
      ),
    );
  }
}

class _ShowInfo extends StatelessWidget {
  final MediaTitle title;
  const _ShowInfo({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.isShow ? 'Show info' : 'Movie info',
              style: AppTextStyles.sectionHeader.copyWith(fontSize: 18)),
          const SizedBox(height: AppSpacing.xs),
          Text('${title.yearLine} • ${title.genres.join(', ')}',
              style: AppTextStyles.subtitle),
          const SizedBox(height: AppSpacing.sm),
          if (title.starRating != null)
            Row(
              children: [
                const _TLogo(),
                const SizedBox(width: AppSpacing.sm),
                for (var i = 0; i < 5; i++)
                  const Icon(Icons.star, size: 14, color: AppColors.accent),
                const SizedBox(width: AppSpacing.xs),
                Text('${title.starRating}/5', style: AppTextStyles.subtitle),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          if (title.synopsis != null)
            Text(title.synopsis!, style: AppTextStyles.body),
          if (title.addedByCount != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Icon(Icons.people, size: 18, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.sm),
                Text('${title.addedByCount} tis. added this ${title.isShow ? 'show' : 'movie'}',
                    style: AppTextStyles.subtitle),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CastRail extends StatelessWidget {
  final List<CastMember> cast;
  const _CastRail({required this.cast});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: cast.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (c, i) {
          final m = cast[i];
          return SizedBox(
            width: AppLayout.castCardW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Poster(
                    width: AppLayout.castPhoto,
                    height: AppLayout.castPhoto,
                    radius: AppRadius.sm,
                    imageAsset: m.photo,
                    label: m.name),
                const SizedBox(height: AppSpacing.xs),
                Text(m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.subtitle
                        .copyWith(color: AppColors.textPrimary)),
                Text(m.role.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.microCaps),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AlsoWatchedRail extends StatelessWidget {
  final ContentRepository repo;
  const _AlsoWatchedRail({required this.repo});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppLayout.railPosterH,
      child: FutureBuilder<List<MediaTitle>>(
        future: repo.trending(MediaKind.show),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: snap.data!.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (c, i) => Stack(
              children: [
                Poster(
                    width: AppLayout.railPosterW,
                    height: AppLayout.railPosterH,
                    imageAsset: snap.data![i].poster,
                    label: snap.data![i].name),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle),
                    child: const Icon(Icons.check,
                        size: 16, color: AppColors.accentInk),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommentsRow extends StatelessWidget {
  final MediaTitle title;
  const _CommentsRow({required this.title});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/series/${title.id}/reviews'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
                child: Text('Comments',
                    style: AppTextStyles.sectionHeader.copyWith(fontSize: 18))),
            Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _EpisodesTab extends StatelessWidget {
  final MediaTitle title;
  const _EpisodesTab({required this.title});
  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child:
              Text('Continue tracking', style: AppTextStyles.rowTitleList),
        ),
        _ContinueRail(title: title),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                  child: Text('All episodes',
                      style: AppTextStyles.rowTitleList)),
              Icon(Icons.check_circle_outline,
                  color: AppColors.textMuted),
            ],
          ),
        ),
        for (final s in title.seasons) _SeasonGroup(title: title, season: s),
        const SizedBox(height: AppSpacing.xl),
      ]),
    );
  }
}

class _ContinueRail extends StatelessWidget {
  final MediaTitle title;
  const _ContinueRail({required this.title});
  @override
  Widget build(BuildContext context) {
    final eps = title.seasons.isEmpty ? <EpisodeRef>[] : title.seasons.first.episodes;
    final slice = eps.length > 3 ? eps.sublist(eps.length - 3) : eps;
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: slice.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (c, i) {
          final ep = slice[i];
          return Container(
            width: 300,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Poster(
                    width: 72,
                    height: 72,
                    imageAsset: title.poster,
                    label: title.name),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(ep.codeWithAbs,
                          style: AppTextStyles.rowTitle.copyWith(fontSize: 16)),
                      Text(ep.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.subtitle),
                    ],
                  ),
                ),
                _EpCheck(episodeId: ep.id),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SeasonGroup extends StatefulWidget {
  final MediaTitle title;
  final SeasonRef season;
  const _SeasonGroup({required this.title, required this.season});
  @override
  State<_SeasonGroup> createState() => _SeasonGroupState();
}

class _SeasonGroupState extends State<_SeasonGroup> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.season;
    // Counts come from AppState (the live source of truth), not the model's
    // seed flags — otherwise the header and progress bar never move when you
    // tick episodes off.
    final appState = context.watch<AppState>();
    final ids = [for (final e in s.episodes) e.id];
    final watched =
        ids.where((id) => appState.isWatched(id)).length;
    final total = ids.length;
    final allWatched = total > 0 && watched == total;
    final progress = total == 0 ? 0.0 : watched / total;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            child: Row(
              children: [
                Text(s.label, style: AppTextStyles.rowTitle),
                const SizedBox(width: AppSpacing.xs),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textPrimary),
                const Spacer(),
                Text('$watched/$total', style: AppTextStyles.microCaps),
                const SizedBox(width: AppSpacing.md),
                // Season-level toggle: marks the whole season watched, or
                // clears it when everything is already ticked.
                WatchCheck(
                  key: Key('seasonCheck-${s.number}'),
                  watched: allWatched,
                  onTap: total == 0
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          context
                              .read<AppState>()
                              .setManyWatched(ids, !allWatched);
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(
                              duration: const Duration(seconds: 2),
                              content: Text(allWatched
                                  ? '${s.label} marked unwatched'
                                  : '${s.label} marked watched'),
                            ));
                        },
                ),
              ],
            ),
          ),
        ),
        WatchProgressBar(progress),
        if (_expanded)
          for (final ep in s.episodes) _EpisodeRowExpanded(title: widget.title, ep: ep),
      ],
    );
  }
}

class _EpisodeRowExpanded extends StatelessWidget {
  final MediaTitle title;
  final EpisodeRef ep;
  const _EpisodeRowExpanded({required this.title, required this.ep});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/series/${title.id}/episode/${ep.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Poster(
                width: 88,
                height: 60,
                imageAsset: ep.still ?? title.banner ?? title.poster,
                label: title.name),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ep.codeWithAbs,
                      style: AppTextStyles.rowTitle.copyWith(fontSize: 16)),
                  Text(ep.title, style: AppTextStyles.subtitle),
                ],
              ),
            ),
            _EpCheck(episodeId: ep.id),
          ],
        ),
      ),
    );
  }
}

class _EpCheck extends StatelessWidget {
  final String episodeId;
  const _EpCheck({required this.episodeId});
  @override
  Widget build(BuildContext context) {
    // AppState alone decides watched-ness. OR-ing the model's seed flag in
    // here used to pin seeded episodes to "watched" forever: the tap wrote
    // false, the flag forced true again, and the control looked dead.
    final watched = context.watch<AppState>().isWatched(episodeId);
    return WatchCheck(
      watched: watched,
      onTap: () =>
          context.read<AppState>().setWatched(episodeId, !watched),
    );
  }
}

class _MoreTab extends StatelessWidget {
  final MediaTitle title;
  const _MoreTab({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Text('WHERE DID YOU WATCH?', style: AppTextStyles.captionCaps),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _provider(Icons.theaters, 'THEATER'),
              _provider(Icons.more_horiz, 'OTHER'),
              _provider(Icons.block, 'UNOFFICIAL', red: true),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('RATE THIS MOVIE', style: AppTextStyles.captionCaps),
          const SizedBox(height: AppSpacing.sm),
          const _StarRow(),
        ],
      ),
    );
  }

  Widget _provider(IconData icon, String label, {bool red = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        children: [
          Container(
            width: AppLayout.providerSquare,
            height: AppLayout.providerSquare,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon,
                color: red ? AppColors.unofficialRed : AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: AppTextStyles.microCaps),
        ],
      ),
    );
  }
}

class _StarRow extends StatefulWidget {
  const _StarRow();
  @override
  State<_StarRow> createState() => _StarRowState();
}

class _StarRowState extends State<_StarRow> {
  int _rating = 0;
  static const _labels = ['BAD', 'OK', 'GOOD', 'GREAT', 'WOW'];
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 5; i++)
          GestureDetector(
            onTap: () => setState(() => _rating = i + 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Column(
                children: [
                  Icon(Icons.star,
                      size: AppLayout.starSize,
                      color: i < _rating
                          ? AppColors.accent
                          : AppColors.textDisabled),
                  Text(_labels[i], style: AppTextStyles.microCaps),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Alternate-artwork picker backed by TVDB's artwork list; tapping an image
/// saves the choice to the signed-in account and applies it app-wide.
class _ArtworkPicker extends StatefulWidget {
  final MediaTitle title;
  final bool poster;
  const _ArtworkPicker({required this.title, required this.poster});
  @override
  State<_ArtworkPicker> createState() => _ArtworkPickerState();
}

class _ArtworkPickerState extends State<_ArtworkPicker> {
  late final Future<List<String>> _future = context
      .read<ContentRepository>()
      .artworkUrls(widget.title.id, posters: widget.poster);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final current = widget.poster
        ? (appState.posterOverride(widget.title.id) ?? widget.title.poster)
        : (appState.bannerOverride(widget.title.id) ?? widget.title.banner);
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.poster ? 'Change poster' : 'Change banner')),
      body: FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accent));
          }
          final urls = snap.data!;
          if (urls.isEmpty) {
            return Center(
              child: Text('No alternate artwork available.',
                  style: AppTextStyles.body),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.sm),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.poster ? 4 : 2,
              childAspectRatio: widget.poster ? 2 / 3 : 16 / 9,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
            ),
            itemCount: urls.length,
            itemBuilder: (c, i) {
              final url = urls[i];
              final selected = url == current;
              return GestureDetector(
                onTap: () {
                  final s = context.read<AppState>();
                  widget.poster
                      ? s.setPoster(widget.title.id, url)
                      : s.setBanner(widget.title.id, url);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.surfaceElevated,
                    content: Text(
                        widget.poster ? 'Poster updated' : 'Banner updated',
                        style: AppTextStyles.body),
                    duration: const Duration(seconds: 1),
                  ));
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                        child: Poster(
                            imageAsset: url, label: widget.title.name)),
                    if (selected)
                      Positioned(
                        left: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.overlayScrim,
                            borderRadius:
                                BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star,
                                  color: AppColors.accent, size: 14),
                              const SizedBox(width: 2),
                              Text('Selected',
                                  style: AppTextStyles.microCaps.copyWith(
                                      color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
