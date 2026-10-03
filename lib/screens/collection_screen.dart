import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../shelf/shelf_layout.dart';
import '../shelf/shelf_view.dart';
import '../shelf/tape_catalog.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Every tracked title as a tape on the shelf, in sections by where the
/// user is with it. Lays out from [AppState] alone, so hundreds of tapes
/// cost nothing until their bays scroll into view.
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  /// Section order and rail-card names.
  static const List<(CollectionGroup, String)> _order = [
    (CollectionGroup.watching, 'WATCHING'),
    (CollectionGroup.notStarted, 'NOT STARTED'),
    (CollectionGroup.completed, 'COMPLETED'),
    (CollectionGroup.stopped, 'STOPPED'),
  ];

  /// Groups [AppState.trackedIds] into shelf sections. Within a section,
  /// the most recently watched first, then the most recently added.
  static List<ShelfSection> sectionsFor(AppState s) {
    final counts = TapeStates.watchedCounts(s);
    final ids = s.trackedIds.reversed.toList();
    final recent = <String, int>{
      for (final id in ids) id: s.lastWatchedAt(id)?.millisecondsSinceEpoch ?? 0,
    };
    final order = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    ids.sort((a, b) {
      final c = recent[b]!.compareTo(recent[a]!);
      return c != 0 ? c : order[a]!.compareTo(order[b]!);
    });
    final groups = <CollectionGroup, List<ShelfTape>>{};
    for (final id in ids) {
      final g = groupOf(s.statusOf(id), counts[id] ?? 0);
      groups
          .putIfAbsent(g, () => [])
          .add(ShelfTape(id, TapeStates.poseOf(id, s, counts[id] ?? 0)));
    }
    return [
      for (final (g, label) in _order)
        if (groups[g] case final tapes?) ShelfSection(label: label, tapes: tapes),
    ];
  }

  static CollectionGroup groupOf(TrackStatus? status, int watched) =>
      switch (status) {
        TrackStatus.completed => CollectionGroup.completed,
        TrackStatus.stopped => CollectionGroup.stopped,
        TrackStatus.watching => CollectionGroup.watching,
        _ => watched > 0 ? CollectionGroup.watching : CollectionGroup.notStarted,
      };

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sections = sectionsFor(appState);
    final total = sections.fold<int>(0, (n, s) => n + s.tapes.length);
    return Scaffold(
      key: const Key('collectionScreen'),
      appBar: AppBar(
        title: Text('Collection', style: AppTextStyles.rowTitle),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/profile'),
        ),
      ),
      body: total == 0
          ? EmptyState(
              title: 'No tapes yet',
              subtitle: 'Track shows and movies to fill your shelves.',
              ctaLabel: 'EXPLORE',
              onCta: () => context.go('/explore/discover'),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                        AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                    child: Text(
                      '$total ${total == 1 ? 'tape' : 'tapes'} · '
                      '${[for (final s in sections) '${s.tapes.length} ${s.label.toLowerCase()}'].join(' · ')}',
                      style: AppTextStyles.subtitle,
                    ),
                  ),
                ),
                SliverShelf(sections: sections),
                SliverToBoxAdapter(
                  child: SizedBox(
                      height: MediaQuery.paddingOf(context).bottom +
                          AppSpacing.xl),
                ),
              ],
            ),
    );
  }
}

/// The collection's sections.
enum CollectionGroup { watching, notStarted, completed, stopped }
