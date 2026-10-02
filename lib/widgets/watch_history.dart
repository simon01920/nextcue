import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  EpisodeRef? _findEpisode(MediaTitle? title) {
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

