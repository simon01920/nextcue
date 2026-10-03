import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../shelf/shelf_layout.dart';
import '../shelf/shelf_view.dart';
import '../shelf/tape_catalog.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// The favourites shelf: each favourite is a VHS tape on a photographic
/// shelf (pre-rendered plates composited with per-title label art, see
/// docs/PLATES.md). Tapes stand by watch state — shrink-wrapped when not
/// started, pulled forward while watching. Tap one to inspect it. Free
/// accounts shelve up to [AppState.favoriteLimitFree] tapes.
class VhsShelf extends StatelessWidget {
  final List<String> ids;
  const VhsShelf({super.key, required this.ids});

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Text('Tap the heart on a show or movie to shelve its tape.',
            style: AppTextStyles.subtitle),
      );
    }
    final appState = context.watch<AppState>();
    final counts = TapeStates.watchedCounts(appState);
    return ShelfColumn(
      sections: [
        ShelfSection(
          label: 'FAVOURITES',
          tapes: [
            for (final id in ids)
              ShelfTape(id, TapeStates.poseOf(id, appState, counts[id] ?? 0)),
          ],
        ),
      ],
    );
  }
}
