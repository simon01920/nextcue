import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'poster.dart';

/// Long-press action sheet for any tracked title (grid tile or list row).
///
/// Everything here mutates [AppState] directly, so the sheet works the same
/// from the watch list, the poster grid, the movies screen and Explore.
Future<void> showTitleActions(
  BuildContext context, {
  required MediaTitle title,
  EpisodeRef? upNext,
}) async {
  HapticFeedback.mediumImpact();
  final appState = context.read<AppState>();

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _TitleActionsSheet(
      title: title,
      upNext: upNext,
      appState: appState,
    ),
  );
}

class _TitleActionsSheet extends StatelessWidget {
  final MediaTitle title;
  final EpisodeRef? upNext;
  final AppState appState;
  const _TitleActionsSheet({
    required this.title,
    required this.upNext,
    required this.appState,
  });

  /// Every aired episode id of the title, used by the bulk actions.
  List<String> get _allEpisodeIds => [
        for (final s in title.seasons)
          for (final e in s.episodes) e.id,
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = appState.statusOf(title.id);
    final fav = appState.isFavorite(title.id);
    final watchedCount = appState.watchedCountFor(title.id);
    final total = _allEpisodeIds.length;
    final ep = upNext;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        // Material (not a decorated Container) so the ListTiles' ink and
        // background render correctly — a DecoratedBox would hide them.
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context, watchedCount, total),
              const Divider(height: 1),

              // --- Episode-level actions -------------------------------
              if (ep != null && !appState.isWatched(ep.id))
                _tile(
                  context,
                  Icons.check_circle_outline,
                  'Mark ${ep.code} watched',
                  subtitle: ep.title,
                  onTap: () => appState.setWatched(ep.id, true),
                ),
              if (appState.watchHistory
                  .any((id) => id.startsWith('${title.id}:')))
                _tile(
                  context,
                  Icons.undo,
                  'Unwatch last episode',
                  onTap: () {
                    final last = appState.watchHistory.firstWhere(
                        (id) => id.startsWith('${title.id}:'),
                        orElse: () => '');
                    if (last.isNotEmpty) appState.setWatched(last, false);
                  },
                ),
              if (total > 0 && watchedCount < total)
                _tile(
                  context,
                  Icons.done_all,
                  'Mark all $total episodes watched',
                  onTap: () => appState.setManyWatched(_allEpisodeIds, true),
                ),
              if (watchedCount > 0)
                _tile(
                  context,
                  Icons.remove_done,
                  'Clear watched history for this title',
                  onTap: () => appState.setManyWatched(_allEpisodeIds, false),
                ),
              const Divider(height: 1),

              // --- Status ----------------------------------------------
              _statusRow(context, status),
              const Divider(height: 1),

              _tile(
                context,
                fav ? Icons.favorite : Icons.favorite_border,
                fav ? 'Remove from favourites' : 'Add to favourites',
                iconColor: fav ? AppColors.love : null,
                onTap: () {
                  final ok = appState.toggleFavorite(title.id);
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Favourites shelf is full (${AppState.favoriteLimitFree}).'),
                    ));
                  }
                },
              ),
              _tile(
                context,
                Icons.open_in_new,
                'Open details',
                onTap: () => context.push(
                    '/${title.kind == MediaKind.movie ? 'movie' : 'series'}/${title.id}'),
              ),
              if (status != null)
                _tile(
                  context,
                  Icons.delete_outline,
                  'Remove from my lists',
                  iconColor: AppColors.error,
                  onTap: () => appState.setStatus(title.id, null),
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int watched, int total) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Poster(
            width: 46,
            height: 66,
            radius: AppRadius.sm,
            imageAsset: appState.posterOverride(title.id) ?? title.poster,
            label: title.name,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.rowTitleList
                        .copyWith(color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 2),
                Text(
                  total > 0 ? '$watched of $total episodes watched' : title.metaLine,
                  style: AppTextStyles.subtitle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(BuildContext context, TrackStatus? current) {
    const labels = {
      TrackStatus.watching: 'Watching',
      TrackStatus.planToWatch: 'Plan to watch',
      TrackStatus.completed: 'Completed',
      TrackStatus.stopped: 'Stopped',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STATUS', style: AppTextStyles.captionCaps),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final entry in labels.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: current == entry.key,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    appState.setStatus(
                        title.id, current == entry.key ? null : entry.key);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String label, {
    String? subtitle,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon,
          color: iconColor ?? Theme.of(context).colorScheme.onSurface),
      title: Text(label,
          style: AppTextStyles.body
              .copyWith(color: Theme.of(context).colorScheme.onSurface)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.subtitle),
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).pop();
        onTap();
      },
    );
  }
}
