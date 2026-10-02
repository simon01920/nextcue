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

/// Episode detail. Interactions (watched-on device, rating, feelings,
/// favorite character) unlock only once the episode is marked watched.
/// The discussion lives inline at the bottom: watched episodes reveal it
/// with a small overscroll pull (with haptic feedback); unwatched episodes
/// keep it behind a spoiler-warning unlock.
class EpisodeDetailScreen extends StatelessWidget {
  final String titleId;
  final String episodeId;
  const EpisodeDetailScreen({
    super.key,
    required this.titleId,
    required this.episodeId,
  });

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    return Scaffold(
      body: ContentColumn(
        child: FutureBuilder<MediaTitle>(
          future: repo.titleById(titleId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent));
            }
            final title = snap.data!;
            return _EpisodeBody(title: title, ep: _find(title));
          },
        ),
      ),
    );
  }

  EpisodeRef _find(MediaTitle title) {
    for (final s in title.seasons) {
      for (final e in s.episodes) {
        if (e.id == episodeId) return e;
      }
    }
    return title.seasons.isNotEmpty
        ? title.seasons.first.episodes.first
        : const EpisodeRef(id: 'x', season: 1, number: 1, title: 'Episode');
  }
}

class _EpisodeBody extends StatefulWidget {
  final MediaTitle title;
  final EpisodeRef ep;
  const _EpisodeBody({required this.title, required this.ep});

  @override
  State<_EpisodeBody> createState() => _EpisodeBodyState();
}

class _EpisodeBodyState extends State<_EpisodeBody> {
  bool _discussionOpen = false;
  double _pull = 0;
  static const double _pullThreshold = 56;

  void _openDiscussion() {
    if (_discussionOpen) return;
    HapticFeedback.mediumImpact();
    setState(() => _discussionOpen = true);
  }

  /// Watched episodes: a small pull past the bottom opens the discussion.
  bool _onScroll(ScrollNotification n, bool watched) {
    if (!watched || _discussionOpen) return false;
    if (n is OverscrollNotification && n.overscroll > 0) {
      _pull += n.overscroll;
      if (_pull >= _pullThreshold) _openDiscussion();
    } else if (n is ScrollEndNotification) {
      _pull = 0;
    }
    return false;
  }

  void _confirmUnlock() {
    final appState = context.read<AppState>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Spoilers ahead',
            style: AppTextStyles.sectionHeader.copyWith(fontSize: 20)),
        content: Text(
          "You haven't marked this episode as watched yet, and the "
          'discussion talks about everything that happens in it.\n\n'
          'Mark it watched first — or peek at your own risk.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('NOT YET',
                style: AppTextStyles.captionCaps
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openDiscussion();
            },
            child: Text('PEEK ANYWAY',
                style: AppTextStyles.captionCaps
                    .copyWith(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: const StadiumBorder()),
            onPressed: () {
              appState.setWatched(widget.ep.id, true);
              Navigator.of(dialogContext).pop();
              _openDiscussion();
            },
            child: Text('MARK AS WATCHED',
                style: AppTextStyles.buttonPillCaps),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final ep = widget.ep;
    final appState = context.watch<AppState>();
    // AppState is the only source of truth; OR-ing the model's seed flag
    // in here made a seeded episode impossible to un-watch.
    final watched = appState.isWatched(ep.id);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) => _onScroll(n, watched),
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          _TopBar(),
          _EpisodeCard(title: title, ep: ep),
          const SizedBox(height: AppSpacing.md),
          if (watched) ...[
            _WatchedOnBlock(episodeId: ep.id),
            const SizedBox(height: AppSpacing.md),
            _RateBlock(episodeId: ep.id),
            const SizedBox(height: AppSpacing.md),
            _FeelBlock(episodeId: ep.id),
            const SizedBox(height: AppSpacing.md),
            _FavoriteChars(title: title, episodeId: ep.id),
            const SizedBox(height: AppSpacing.md),
          ] else
            const _LockedInteractionsHint(),
          _EpisodeInfo(title: title, ep: ep),
          const SizedBox(height: AppSpacing.lg),
          _DiscussionSection(
            titleId: title.id,
            watched: watched,
            open: _discussionOpen,
            onPullHintTap: _openDiscussion,
            onUnlockTap: _confirmUnlock,
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down,
                color: AppColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          const Spacer(),
          for (var i = 0; i < 6; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == 0 ? AppColors.accent : AppColors.textDisabled,
                shape: BoxShape.circle,
              ),
            ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final MediaTitle title;
  final EpisodeRef ep;
  const _EpisodeCard({required this.title, required this.ep});
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // AppState is the only source of truth; OR-ing the model's seed flag
    // in here made a seeded episode impossible to un-watch.
    final watched = appState.isWatched(ep.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Poster(
                        radius: AppRadius.md,
                        imageAsset: ep.still ?? title.banner ?? title.poster,
                        label: title.name,
                      ),
                      // Scrim keeps the episode code readable on stills.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.45, 1],
                            colors: [Colors.transparent, Color(0xB3000000)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: AppSpacing.sm,
                left: AppSpacing.sm,
                child: ShowPill(title.name,
                    onTap: () => context.go('/series/${title.id}')),
              ),
              const Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Icon(Icons.ios_share, color: Colors.white, size: 20),
              ),
              Positioned(
                left: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ep.codeWithAbs,
                        style: AppTextStyles.rowTitle.copyWith(fontSize: 22)),
                    Text(ep.title, style: AppTextStyles.subtitle),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.xs),
                Text(_fmtDate(ep.airDate), style: AppTextStyles.subtitle),
                const SizedBox(width: AppSpacing.lg),
                Icon(Icons.visibility,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.xs),
                Text(watched ? 'Watched' : 'Not watched',
                    style: AppTextStyles.subtitle),
                const Spacer(),
                WatchCheck(
                  watched: watched,
                  onTap: () =>
                      context.read<AppState>().setWatched(ep.id, !watched),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime? d) =>
      d == null ? '—' : '${d.day}. ${d.month}. ${d.year}';
}

/// Shown instead of the interaction blocks while the episode is unwatched.
class _LockedInteractionsHint extends StatelessWidget {
  const _LockedInteractionsHint();
  @override
  Widget build(BuildContext context) {
    return _Block(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline,
              size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Mark the episode as watched to rate it, react and pick '
              'your favorite.',
              style: AppTextStyles.subtitle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Device the episode was watched on (replaces "where did you watch").
class _WatchedOnBlock extends StatelessWidget {
  final String episodeId;
  const _WatchedOnBlock({required this.episodeId});

  static const _devices = [
    (Icons.tv, 'TV'),
    (Icons.smartphone, 'PHONE'),
    (Icons.tablet_mac, 'TABLET'),
    (Icons.laptop_mac, 'LAPTOP'),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<AppState>().deviceOf(episodeId);
    return _Block(
      child: Column(
        children: [
          Text('WATCHED ON', style: AppTextStyles.captionCaps),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in _devices)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: GestureDetector(
                    onTap: () =>
                        context.read<AppState>().setDevice(episodeId, d.$2),
                    child: Column(
                      children: [
                        Container(
                          width: AppLayout.providerSquare,
                          height: AppLayout.providerSquare,
                          decoration: BoxDecoration(
                            color: selected == d.$2
                                ? AppColors.surfaceElevated
                                : AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            border: selected == d.$2
                                ? Border.all(color: AppColors.accent)
                                : null,
                          ),
                          child: Icon(d.$1,
                              color: selected == d.$2
                                  ? AppColors.accentAlt
                                  : AppColors.textPrimary),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(d.$2, style: AppTextStyles.microCaps),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RateBlock extends StatelessWidget {
  final String episodeId;
  const _RateBlock({required this.episodeId});
  static const _labels = ['BAD', 'OK', 'GOOD', 'GREAT', 'WOW'];
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final rating = appState.ratingOf(episodeId) ?? 0;
    return _Block(
      child: Column(
        children: [
          Text('RATE THIS EPISODE', style: AppTextStyles.captionCaps),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 5; i++)
                GestureDetector(
                  onTap: () =>
                      context.read<AppState>().rate(episodeId, i + 1),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Column(
                      children: [
                        Icon(Icons.star,
                            size: AppLayout.starSize,
                            color: i < rating
                                ? AppColors.accent
                                : AppColors.textDisabled),
                        Text(_labels[i], style: AppTextStyles.microCaps),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeelBlock extends StatelessWidget {
  final String episodeId;
  const _FeelBlock({required this.episodeId});
  static const _emotions = [
    ('😵', 'SHOCKED'), ('😫', 'FRUSTRATED'), ('😭', 'SAD'), ('🤔', 'REFLECTIVE'),
    ('🥹', 'TOUCHED'), ('😆', 'AMUSED'), ('😱', 'SCARED'), ('😑', 'BORED'),
    ('😌', 'UNDERSTOOD'), ('🤩', 'THRILLED'), ('🙃', 'CONFUSED'), ('😬', 'TENSE'),
  ];
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selected = appState.reactionOf(episodeId);
    return _Block(
      child: Column(
        children: [
          Text('HOW DID YOU FEEL?', style: AppTextStyles.captionCaps),
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.85,
            children: [
              for (final e in _emotions)
                GestureDetector(
                  onTap: () =>
                      context.read<AppState>().react(episodeId, e.$2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: AppLayout.emotionChip,
                        height: AppLayout.emotionChip,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected == e.$2
                              ? AppColors.surfaceElevated
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: selected == e.$2
                              ? Border.all(color: AppColors.accent)
                              : null,
                        ),
                        child: Text(e.$1,
                            style: const TextStyle(fontSize: 28)),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(e.$2, style: AppTextStyles.microCaps),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavoriteChars extends StatelessWidget {
  final MediaTitle title;
  final String episodeId;
  const _FavoriteChars({required this.title, required this.episodeId});
  @override
  Widget build(BuildContext context) {
    if (title.cast.isEmpty) return const SizedBox.shrink();
    final selected = context.watch<AppState>().favoriteCharOf(episodeId);
    return _Block(
      child: Column(
        children: [
          Text('WHO WAS YOUR FAVORITE?', style: AppTextStyles.captionCaps),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: title.cast.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.sm),
              itemBuilder: (c, i) {
                final member = title.cast[i];
                final isSel = selected == member.name;
                return GestureDetector(
                  onTap: () => context
                      .read<AppState>()
                      .setFavoriteChar(episodeId, member.name),
                  child: SizedBox(
                    width: 88,
                    child: Column(
                      children: [
                        Container(
                          decoration: isSel
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                      AppRadius.sm + 2),
                                  border: Border.all(
                                      color: AppColors.accent, width: 2),
                                )
                              : null,
                          child: Poster(
                              width: 84,
                              height: 84,
                              radius: AppRadius.sm,
                              imageAsset: member.photo,
                              label: member.name),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(member.name.split(' ').first.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.microCaps.copyWith(
                                color: isSel
                                    ? AppColors.accentAlt
                                    : AppTextStyles.microCaps.color)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeInfo extends StatelessWidget {
  final MediaTitle title;
  final EpisodeRef ep;
  const _EpisodeInfo({required this.title, required this.ep});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Episode info',
              style: AppTextStyles.sectionHeader.copyWith(fontSize: 18)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                const Icon(Icons.star, size: 14, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Text('${ep.rating ?? 4.7}/5', style: AppTextStyles.subtitle),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(ep.synopsis ?? 'Episode synopsis.', style: AppTextStyles.body),
        ],
      ),
    );
  }
}

/// Inline discussion at the end of the page.
/// Watched + closed: pull-up hint (overscroll or tap reveals, with haptic).
/// Unwatched: locked card with a spoiler-warning unlock dialog.
/// Open: the comment thread.
class _DiscussionSection extends StatelessWidget {
  final String titleId;
  final bool watched;
  final bool open;
  final VoidCallback onPullHintTap;
  final VoidCallback onUnlockTap;
  const _DiscussionSection({
    required this.titleId,
    required this.watched,
    required this.open,
    required this.onPullHintTap,
    required this.onUnlockTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.slide,
      curve: AppMotion.glide,
      alignment: Alignment.topCenter,
      child: open
          ? _DiscussionThread(titleId: titleId)
          : watched
              ? _PullHint(onTap: onPullHintTap)
              : _LockedDiscussion(onUnlockTap: onUnlockTap),
    );
  }
}

class _PullHint extends StatelessWidget {
  final VoidCallback onTap;
  const _PullHint({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          children: [
            Icon(Icons.keyboard_arrow_up,
                color: AppColors.textMuted, size: 22),
            const SizedBox(height: AppSpacing.xs),
            Text('Pull up for the discussion',
                style: AppTextStyles.captionCaps),
          ],
        ),
      ),
    );
  }
}

class _LockedDiscussion extends StatelessWidget {
  final VoidCallback onUnlockTap;
  const _LockedDiscussion({required this.onUnlockTap});
  @override
  Widget build(BuildContext context) {
    return _Block(
      child: Column(
        children: [
          Icon(Icons.lock_outline,
              color: AppColors.textMuted, size: 28),
          const SizedBox(height: AppSpacing.sm),
          Text('Discussion locked', style: AppTextStyles.rowTitleList),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Finish the episode first — spoilers live here.',
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: onUnlockTap,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.borderSubtle),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: AppSpacing.md),
            ),
            child: Text('UNLOCK DISCUSSION',
                style: AppTextStyles.buttonPillCaps
                    .copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _DiscussionThread extends StatelessWidget {
  final String titleId;
  const _DiscussionThread({required this.titleId});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Discussion',
              style: AppTextStyles.sectionHeader.copyWith(fontSize: 18)),
          const SizedBox(height: AppSpacing.md),
          FutureBuilder<List<Comment>>(
            future: repo.comments(titleId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: AppColors.accent),
                    ),
                  ),
                );
              }
              final comments = snap.data!;
              if (comments.isEmpty) {
                return Text('No comments yet — be the first.',
                    style: AppTextStyles.subtitle);
              }
              return Column(
                children: [
                  for (final c in comments) _CommentTile(comment: c),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  const _CommentTile({required this.comment});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppLayout.avatarSm,
            height: AppLayout.avatarSm,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: Text(
              comment.user.isEmpty
                  ? '?'
                  : comment.user[0].toUpperCase(),
              style: AppTextStyles.rowTitleList,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.user,
                        style: AppTextStyles.rowTitleList
                            .copyWith(fontSize: 14)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(comment.date, style: AppTextStyles.subtitle),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(comment.body, style: AppTextStyles.body),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.favorite_border,
                        size: 14, color: AppColors.textMuted),
                    const SizedBox(width: AppSpacing.xs),
                    Text('${comment.likes}', style: AppTextStyles.subtitle),
                    const SizedBox(width: AppSpacing.lg),
                    Icon(Icons.chat_bubble_outline,
                        size: 13, color: AppColors.textMuted),
                    const SizedBox(width: AppSpacing.xs),
                    Text('${comment.replies}',
                        style: AppTextStyles.subtitle),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final Widget child;
  const _Block({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: AppColors.bgPrimary,
      child: child,
    );
  }
}
