import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/poster.dart';
import '../widgets/title_actions.dart';

/// Full-bleed browse wall with a Movies / TV Shows segmented toggle — the
/// destination for the "Browse all" buttons on Discover.
class BrowseScreen extends StatefulWidget {
  final MediaKind initialKind;
  const BrowseScreen({super.key, this.initialKind = MediaKind.show});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late MediaKind _kind = widget.initialKind;
  final Map<MediaKind, Future<List<MediaTitle>>> _futures = {};

  Future<List<MediaTitle>> _future(BuildContext context, MediaKind kind) =>
      _futures.putIfAbsent(
          kind, () => context.read<ContentRepository>().trending(kind));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: ContentColumn(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SegmentedButton<MediaKind>(
                segments: const [
                  ButtonSegment(
                    value: MediaKind.movie,
                    icon: Icon(Icons.movie_outlined, size: 18),
                    label: Text('Movies'),
                  ),
                  ButtonSegment(
                    value: MediaKind.show,
                    icon: Icon(Icons.tv, size: 18),
                    label: Text('TV Shows'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<MediaTitle>>(
                future: _future(context, _kind),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text('Couldn’t load titles.\n${snap.error}',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.subtitle),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: AppColors.accent),
                      ),
                    );
                  }
                  final titles = snap.data!;
                  if (titles.isEmpty) {
                    return Center(
                      child: Text('Nothing to browse right now.',
                          style: AppTextStyles.subtitle),
                    );
                  }
                  final cols = AppBreakpoints.gridColumns(
                      MediaQuery.sizeOf(context).width);
                  return GridView.builder(
                    padding: EdgeInsets.only(
                      left: AppSpacing.sm,
                      right: AppSpacing.sm,
                      bottom: MediaQuery.paddingOf(context).bottom +
                          AppSpacing.lg,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: 2 / 3,
                      crossAxisSpacing: AppLayout.gridGap,
                      mainAxisSpacing: AppLayout.gridGap,
                    ),
                    itemCount: titles.length,
                    itemBuilder: (context, i) =>
                        _BrowseTile(title: titles[i], scheme: scheme),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseTile extends StatelessWidget {
  final MediaTitle title;
  final ColorScheme scheme;
  const _BrowseTile({required this.title, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tracked = appState.statusOf(title.id) != null;
    return GestureDetector(
      onTap: () => context.push(
          '/${title.kind == MediaKind.movie ? 'movie' : 'series'}/${title.id}'),
      onLongPress: () => showTitleActions(context, title: title),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Poster(
            imageAsset: appState.posterOverride(title.id) ?? title.poster,
            label: title.name,
          ),
          Positioned(
            top: 4,
            right: 4,
            child: AddToListButton(title: title, tracked: tracked),
          ),
        ],
      ),
    );
  }
}
