import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'poster.dart';

/// Recently-watched history, newest first, with one-tap undo.
///
/// Mirrors the behaviour the source app had: overscroll the top of the watch
/// list and your history slides in, so an episode ticked off by accident can
/// be put straight back.
Future<void> showWatchHistory(BuildContext context) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _WatchHistorySheet(),
  );
}

class _WatchHistorySheet extends StatelessWidget {
  const _WatchHistorySheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();
    final history = appState.watchHistory;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg)),
        ),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.history, color: scheme.onSurface),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Watch history',
                        style: AppTextStyles.sectionHeader
                            .copyWith(color: scheme.onSurface)),
                  ),
                  Text('${history.length} episodes',
                      style: AppTextStyles.subtitle),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          'Nothing watched yet.\nEpisodes you tick off show up '
                          'here so you can undo mistakes.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.subtitle,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom +
                              AppSpacing.md),
                      itemCount: history.length,
                      itemBuilder: (context, i) =>
                          _HistoryRow(episodeId: history[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One history entry. Episode ids are `titleId:season:number`, so the title
/// is resolved through the repository (cached) for the show name and artwork.
class _HistoryRow extends StatelessWidget {
  final String episodeId;
  const _HistoryRow({required this.episodeId});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();
    final parts = episodeId.split(':');
    final titleId = parts.first;
    final code = parts.length >= 3
        ? 'S${parts[1].padLeft(2, '0')} | E${parts[2].padLeft(2, '0')}'
        : '';
    final when = appState.watchedAt(episodeId);

    return FutureBuilder<MediaTitle>(
      future: context.read<ContentRepository>().titleById(titleId),
      builder: (context, snap) {
        final title = snap.data;
        final episode = _findEpisode(title);
        return ListTile(
          leading: Poster(
            width: 44,
            height: 62,
            radius: AppRadius.sm,
            imageAsset: episode?.still ??
                appState.posterOverride(titleId) ??
                title?.poster,
            label: title?.name,
          ),
          title: Text(
            title?.name ?? 'Loading…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.rowTitleList.copyWith(color: scheme.onSurface),
          ),
          subtitle: Text(
            [
              if (code.isNotEmpty) code,
              if (episode != null) episode.title,
              if (when != null) _ago(when),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.subtitle,
          ),
          trailing: TextButton.icon(
            onPressed: () {
              HapticFeedback.selectionClick();
              context.read<AppState>().setWatched(episodeId, false);
            },
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Unwatch'),
          ),
        );
      },
    );
  }

  EpisodeRef? _findEpisode(MediaTitle? title) => findEpisode(title, episodeId);

  static EpisodeRef? findEpisode(MediaTitle? title, String episodeId) {
    if (title == null) return null;
    for (final s in title.seasons) {
      for (final e in s.episodes) {
        if (e.id == episodeId) return e;
      }
    }
    return null;
  }

  static String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${(d.inDays / 30).floor()}mo ago';
  }
}

/// Wraps a scrollable so that dragging down past the top by [threshold] of the
/// screen height fires [onReveal] once, with a haptic tick at the halfway
/// point so the gesture is discoverable by feel.
class OverscrollReveal extends StatefulWidget {
  final Widget child;
  final VoidCallback onReveal;
  final double threshold; // fraction of screen height
  const OverscrollReveal({
    super.key,
    required this.child,
    required this.onReveal,
    this.threshold = 0.33,
  });

  @override
  State<OverscrollReveal> createState() => _OverscrollRevealState();
}

class _OverscrollRevealState extends State<OverscrollReveal> {
  /// Accumulated pull for clamping physics, which holds the position at the
  /// edge and reports the surplus as overscroll deltas instead.
  double _clampPull = 0;
  bool _armed = false;
  bool _fired = false;

  void _reset() {
    _clampPull = 0;
    _armed = false;
    _fired = false;
  }

  void _consider(double pull, double trigger) {
    if (!_armed && pull > trigger / 2) {
      _armed = true;
      HapticFeedback.lightImpact();
    }
    if (!_fired && pull >= trigger) {
      _fired = true;
      HapticFeedback.heavyImpact();
      widget.onReveal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trigger = MediaQuery.sizeOf(context).height * widget.threshold;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Only the list itself, never a nested horizontal rail.
        if (n.depth != 0) return false;

        if (n is ScrollStartNotification || n is ScrollEndNotification) {
          _reset();
          return false;
        }

        // Bouncing physics (what this app uses) never emits an
        // OverscrollNotification: the position simply travels past the top,
        // so the pull has to be measured against minScrollExtent.
        final m = n.metrics;
        var pull = m.minScrollExtent - m.pixels;
        if (pull < 0) pull = 0;

        // Clamping physics pins the position at the edge and reports the
        // remainder as overscroll deltas, so accumulate those too.
        if (n is OverscrollNotification && n.overscroll < 0) {
          _clampPull += -n.overscroll;
        }
        if (_clampPull > pull) pull = _clampPull;

        _consider(pull, trigger);
        return false;
      },
      child: widget.child,
    );
  }
}


// ---------------------------------------------------------------------------
// Inline history above the watch list (TV Time's "scroll up to see what you
// watched"). Lives in the part of a CustomScrollView *before* its centre
// sliver, so it grows upward from the watch list: the list opens exactly
// where it always did, and scrolling up walks back through time.
// ---------------------------------------------------------------------------

/// How many recent episodes the inline history shows; the full history is
/// in the sheet ([showWatchHistory]).
const int inlineHistoryLimit = 300;

sealed class _HistoryItem {
  const _HistoryItem();
}

class _DayHeader extends _HistoryItem {
  final String label;
  const _DayHeader(this.label);
}

class _Episode extends _HistoryItem {
  final String id;
  const _Episode(this.id);
}

class _HistoryTop extends _HistoryItem {
  final int shown, total;
  const _HistoryTop(this.shown, this.total);
}

/// Items in sliver order: index 0 sits right above the watch list (the
/// newest episode); higher indexes are further up the screen (older).
/// Each day's header comes after that day's episodes, so it renders above
/// them.
List<_HistoryItem> _historyItems(AppState s, DateTime now) {
  final all = s.watchHistory; // newest first
  final ids = all.take(inlineHistoryLimit).toList();
  final items = <_HistoryItem>[];
  String? day;
  for (final id in ids) {
    final label = _dayLabel(s.watchedAt(id), now);
    if (day != null && label != day) items.add(_DayHeader(day));
    day = label;
    items.add(_Episode(id));
  }
  if (day != null) items.add(_DayHeader(day));
  if (ids.isNotEmpty) items.add(_HistoryTop(ids.length, all.length));
  return items;
}

String _dayLabel(DateTime? when, DateTime now) {
  if (when == null) return 'EARLIER';
  final d0 = DateTime(now.year, now.month, now.day);
  final d = DateTime(when.year, when.month, when.day);
  final days = d0.difference(d).inDays;
  if (days == 0) return 'TODAY';
  if (days == 1) return 'YESTERDAY';
  const wd = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const mo = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
  ];
  final base = '${wd[d.weekday - 1]} ${d.day} ${mo[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// The history sliver. Put it before the `center` sliver of a
/// CustomScrollView.
class InlineWatchHistory extends StatelessWidget {
  const InlineWatchHistory({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final items = _historyItems(appState, DateTime.now());
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => switch (items[i]) {
        _DayHeader(:final label) => _HistoryDayHeader(label),
        _Episode(:final id) => WatchedEpisodeRow(key: ValueKey(id), episodeId: id),
        _HistoryTop(:final shown, :final total) =>
          _HistoryTopCap(shown: shown, total: total),
      },
    );
  }
}

class _HistoryDayHeader extends StatelessWidget {
  final String label;
  const _HistoryDayHeader(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
      child: Text(label, style: AppTextStyles.captionCaps),
    );
  }
}

class _HistoryTopCap extends StatelessWidget {
  final int shown, total;
  const _HistoryTopCap({required this.shown, required this.total});
  @override
  Widget build(BuildContext context) {
    final more = total > shown;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xxl, AppSpacing.md, AppSpacing.md),
      child: Column(
        children: [
          Icon(Icons.history, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.xs),
          Text(
            more
                ? 'Your last $shown episodes'
                : "That's everything you've watched",
            style: AppTextStyles.subtitle,
          ),
          if (more)
            TextButton(
              onPressed: () => showWatchHistory(context),
              child: Text('SEE FULL HISTORY ($total)',
                  style: AppTextStyles.captionCaps
                      .copyWith(color: AppColors.accentAlt)),
            ),
        ],
      ),
    );
  }
}

/// A watched episode, styled as the faded twin of the watch-list row: the
/// filled check un-watches it (with an undo snackbar).
class WatchedEpisodeRow extends StatelessWidget {
  final String episodeId;
  const WatchedEpisodeRow({super.key, required this.episodeId});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final parts = episodeId.split(':');
    final titleId = parts.first;
    final code = parts.length >= 3
        ? 'S${parts[1].padLeft(2, '0')} | E${parts[2].padLeft(2, '0')}'
        : '';
    final when = appState.watchedAt(episodeId);

    return FutureBuilder<MediaTitle>(
      future: context.read<ContentRepository>().titleById(titleId),
      builder: (context, snap) {
        final title = snap.data;
        final episode = _HistoryRow.findEpisode(title, episodeId);
        return InkWell(
          onTap: () => context.push(
              '/${titleId.startsWith('movie') ? 'movie' : 'series'}/$titleId'),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Opacity(
                  opacity: 0.55,
                  child: Poster(
                    width: 52,
                    height: 76,
                    radius: AppRadius.sm,
                    imageAsset:
                        appState.posterOverride(titleId) ?? title?.poster,
                    label: title?.name,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title?.name ?? ' ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.rowTitleList
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (code.isNotEmpty) code,
                          if (episode != null && episode.title.isNotEmpty)
                            episode.title,
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.subtitle,
                      ),
                      if (when != null) ...[
                        const SizedBox(height: 2),
                        Text('Watched ${_HistoryRow._ago(when)}',
                            style: AppTextStyles.microCaps),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('unwatch-$episodeId'),
                  tooltip: 'Mark as not watched',
                  onPressed: () => _unwatch(context),
                  icon: const Icon(Icons.check_circle,
                      color: AppColors.accent, size: 30),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _unwatch(BuildContext context) {
    final state = context.read<AppState>();
    final at = state.watchedAt(episodeId);
    HapticFeedback.selectionClick();
    state.setWatched(episodeId, false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: const Text('Marked as not watched'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () => state.restoreWatched(episodeId, at),
      ),
    ));
  }
}
