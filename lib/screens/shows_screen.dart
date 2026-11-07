import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/poster.dart';
import '../widgets/swipe_to_watch.dart';
import '../widgets/title_actions.dart';
import '../widgets/top_tabs.dart';
import '../widgets/watch_history.dart';

class ShowsScreen extends StatefulWidget {
  final String tab;
  const ShowsScreen({super.key, required this.tab});

  @override
  State<ShowsScreen> createState() => _ShowsScreenState();
}

class _ShowsScreenState extends State<ShowsScreen> {
  bool _grid = false;
  bool _upcomingGrid = false;
  bool _calendar = false;
  int _prevTab = 0;

  int get _tabIndex => widget.tab == 'upcoming' ? 1 : 0;

  @override
  void didUpdateWidget(ShowsScreen old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      _prevTab = old.tab == 'upcoming' ? 1 : 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final body = _tabIndex == 0
        ? _WatchlistBody(repo: repo, grid: _grid)
        : _UpcomingBody(
            repo: repo, calendar: _calendar, grid: _upcomingGrid);
    return Column(
      key: const Key('showsScreen'),
      children: [
        TopTabs(
          key: const Key('showsTopTabs'),
          labels: const ['WATCH LIST', 'UPCOMING'],
          index: _tabIndex,
          onChanged: (i) =>
              context.go('/shows/${i == 0 ? 'watchlist' : 'upcoming'}'),
        ),
        _Toolbar(
          upcoming: _tabIndex == 1,
          grid: _tabIndex == 1 ? _upcomingGrid : _grid,
          calendar: _calendar,
          onToggleGrid: () => setState(() {
            if (_tabIndex == 1) {
              _upcomingGrid = !_upcomingGrid;
              // Grid and calendar are mutually exclusive views.
              if (_upcomingGrid) _calendar = false;
            } else {
              _grid = !_grid;
            }
          }),
          onToggleCalendar: () => setState(() {
            _calendar = !_calendar;
            if (_calendar) _upcomingGrid = false;
          }),
        ),
        Expanded(
          // Slide the tab content in from the side it lives on.
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

class _Toolbar extends StatelessWidget {
  final bool upcoming;
  final bool grid;
  final bool calendar;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleCalendar;
  const _Toolbar({
    required this.upcoming,
    required this.grid,
    required this.calendar,
    required this.onToggleGrid,
    required this.onToggleCalendar,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: 0),
      child: Row(
        children: [
          // Calendar view toggle — Upcoming only, opposite the grid icon.
          if (upcoming)
            IconButton(
              key: const Key('upcomingCalendarToggle'),
              icon: Icon(
                  calendar ? Icons.view_list_outlined : Icons.calendar_month,
                  size: 22,
                  color: AppColors.textPrimary),
              onPressed: onToggleCalendar,
            ),
          const Spacer(),
          // Grid/list toggle is available on both tabs.
          IconButton(
            key: Key(upcoming ? 'upcomingGridToggle' : 'showsGridToggle'),
            icon: Icon(grid ? Icons.view_agenda_outlined : Icons.grid_view,
                size: 22, color: AppColors.textPrimary),
            onPressed: onToggleGrid,
          ),
        ],
      ),
    );
  }
}

/// Memoizes the watch-list future against AppState.revision so swipes and
/// status changes refresh the list without refetching on every rebuild.
class _WatchlistBody extends StatefulWidget {
  final ContentRepository repo;
  final bool grid;
  const _WatchlistBody({required this.repo, required this.grid});
  @override
  State<_WatchlistBody> createState() => _WatchlistBodyState();
}

class _WatchlistBodyState extends State<_WatchlistBody> {
  Future<List<WatchlistEntry>>? _future;
  int _revision = -1;
  final Key _centerKey = UniqueKey();

  static List<Widget> _section(String label, List<WatchlistEntry> entries) {
    if (entries.isEmpty) return const [];
    return [
      SliverToBoxAdapter(child: SectionChip(label)),
      SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (context, i) =>
            EpisodeRow(key: ValueKey(entries[i].title.id), entry: entries[i]),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (_future == null || appState.revision != _revision) {
      _revision = appState.revision;
      _future = widget.repo.showWatchlist();
    }
    return FutureBuilder<List<WatchlistEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return _ErrorBody(error: '${snap.error}');
        if (!snap.hasData) return const _Loading();
        final entries = snap.data!;
        if (entries.isEmpty) {
          return EmptyState(
            title: 'Your watchlist is empty!',
            subtitle: 'Add shows you want to watch.',
            ctaLabel: 'BROWSE ALL SHOWS',
            onCta: () => context.go('/explore/discover'),
          );
        }
        if (widget.grid) return _PosterGrid(entries: entries);

        // Categorized watch list: caught-up shows leave the main pile into
        // a collapsible section on top; the rest split by progress and
        // recency (stale = nothing watched in 14+ days).
        final caughtUp =
            entries.where((e) => e.upNext == null).toList();
        final active = entries.where((e) => e.upNext != null).toList();
        final now = DateTime.now();
        bool isStale(WatchlistEntry e) {
          final last = appState.lastWatchedAt(e.title.id);
          return last != null && now.difference(last).inDays >= 14;
        }

        final continueWatching = active
            .where((e) =>
                appState.watchedCountFor(e.title.id) > 0 && !isStale(e))
            .toList();
        final stale = active
            .where((e) =>
                appState.watchedCountFor(e.title.id) > 0 && isStale(e))
            .toList();
        final notStarted = active
            .where((e) => appState.watchedCountFor(e.title.id) == 0)
            .toList();

        // TV Time's layout: the watch list opens where it always did, and
        // scrolling *up* from it walks back through what you watched (the
        // history slivers sit before the centre sliver, so they grow
        // upward and never push the list down).
        final hasHistory = appState.watchedEpisodeTotal > 0;
        return CustomScrollView(
          center: _centerKey,
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            if (hasHistory) const InlineWatchHistory(),
            SliverToBoxAdapter(
              key: _centerKey,
              child: _HistoryHint(hasHistory: hasHistory),
            ),
            if (caughtUp.isNotEmpty)
              SliverToBoxAdapter(child: _CaughtUpSection(entries: caughtUp)),
            ..._section('CONTINUE WATCHING', continueWatching),
            ..._section("HAVEN'T WATCHED FOR A WHILE", stale),
            ..._section('NOT STARTED', notStarted),
            // Bottom inset keeps the last row clear of the floating glass nav.
            SliverPadding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom),
            ),
          ],
        );
      },
    );
  }
}

class _PosterGrid extends StatelessWidget {
  final List<WatchlistEntry> entries;
  const _PosterGrid({required this.entries});
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final width = MediaQuery.sizeOf(context).width;
    final cols = AppBreakpoints.gridColumns(width);
    return GridView.builder(
      padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: MediaQuery.paddingOf(context).bottom),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        childAspectRatio: 2 / 3.2,
        crossAxisSpacing: AppLayout.gridGap,
        mainAxisSpacing: AppLayout.gridGap,
      ),
      itemCount: entries.length,
      itemBuilder: (c, i) {
        final e = entries[i];
        final total = e.title.seasons
            .fold<int>(0, (sum, s) => sum + s.episodes.length);
        final watched = appState.watchedCountFor(e.title.id);
        final progress = total == 0 ? 0.0 : watched / total;
        return GestureDetector(
          onTap: () => context.push('/series/${e.title.id}'),
          onLongPress: () =>
              showTitleActions(context, title: e.title, upNext: e.upNext),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Poster(
                      imageAsset:
                          appState.posterOverride(e.title.id) ?? e.title.poster,
                      label: e.title.name,
                    ),
                    if (e.unwatchedAhead > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text('+${e.unwatchedAhead}',
                              style: AppTextStyles.microCaps
                                  .copyWith(color: AppColors.accentInk)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              WatchProgressBar(progress),
            ],
          ),
        );
      },
    );
  }
}

class _UpcomingBody extends StatefulWidget {
  final ContentRepository repo;
  final bool calendar;
  final bool grid;
  const _UpcomingBody({
    required this.repo,
    this.calendar = false,
    this.grid = false,
  });
  @override
  State<_UpcomingBody> createState() => _UpcomingBodyState();
}

class _UpcomingBodyState extends State<_UpcomingBody> {
  Future<List<UpcomingItem>>? _future;
  int _revision = -1;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (_future == null || appState.revision != _revision) {
      _revision = appState.revision;
      _future = widget.repo.showUpcoming();
    }
    return FutureBuilder<List<UpcomingItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return _ErrorBody(error: '${snap.error}');
        if (!snap.hasData) return const _Loading();
        final items = snap.data!;
        if (items.isEmpty) {
          return const EmptyState(
            title: 'Nothing upcoming yet!',
            subtitle: 'Episodes of shows you track will show up here.',
            ctaLabel: 'BROWSE ALL SHOWS',
          );
        }
        if (widget.calendar) return _UpcomingCalendar(items: items);
        if (widget.grid) return _UpcomingGrid(items: items);
        final thisWeek = items.where((i) => (i.daysUntil ?? 0) <= 7).toList();
        final later = items.where((i) => (i.daysUntil ?? 0) > 7).toList();
        return ListView(
          padding:
              EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          children: [
            if (thisWeek.isNotEmpty) const SectionChip('THIS WEEK'),
            for (final it in thisWeek) UpcomingRow(item: it),
            if (later.isNotEmpty) const SectionChip('LATER'),
            for (final it in later) UpcomingRow(item: it),
          ],
        );
      },
    );
  }
}

/// Discoverability affordance for the pull-down history gesture. Sits at the
/// very top of the watch list, so it is only visible while overscrolling.
class _HistoryHint extends StatelessWidget {
  final bool hasHistory;
  const _HistoryHint({required this.hasHistory});
  @override
  Widget build(BuildContext context) {
    if (!hasHistory) return const SizedBox(height: AppSpacing.xs);
    return Padding(
      padding: const EdgeInsets.only(
          top: AppSpacing.xs, bottom: AppSpacing.xs),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.keyboard_double_arrow_up,
                size: 14, color: AppColors.textDisabled),
            const SizedBox(width: AppSpacing.xs),
            Text('Scroll up for recently watched',
                style: AppTextStyles.microCaps),
          ],
        ),
      ),
    );
  }
}

/// Poster-tile view of upcoming episodes, matching the grid toggle on the
/// watch list. Each tile shows the countdown over the episode still, and
/// long-press opens the same actions sheet as everywhere else.
class _UpcomingGrid extends StatelessWidget {
  final List<UpcomingItem> items;
  const _UpcomingGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final cols = AppBreakpoints.gridColumns(MediaQuery.sizeOf(context).width);
    return GridView.builder(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.sm,
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        childAspectRatio: 2 / 3.3,
        crossAxisSpacing: AppLayout.gridGap,
        mainAxisSpacing: AppLayout.gridGap,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        final days = it.daysUntil;
        return GestureDetector(
          onTap: () => context.push('/series/${it.titleId}'),
          onLongPress: () async {
            final title = await repo.titleById(it.titleId);
            if (context.mounted) {
              await showTitleActions(context, title: title, upNext: it.episode);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Poster(
                        imageAsset: it.episode.still ?? it.poster,
                        label: it.showName),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          days == null || days <= 0 ? 'TODAY' : '${days}d',
                          style: AppTextStyles.microCaps
                              .copyWith(color: AppColors.accentInk),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(it.episode.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.microCaps),
            ],
          ),
        );
      },
    );
  }
}

/// Month calendar of upcoming episodes: days with airings carry a red dot
/// (count badge for 2+); tapping a day lists its episodes below.
class _UpcomingCalendar extends StatefulWidget {
  final List<UpcomingItem> items;
  const _UpcomingCalendar({required this.items});
  @override
  State<_UpcomingCalendar> createState() => _UpcomingCalendarState();
}

class _UpcomingCalendarState extends State<_UpcomingCalendar> {
  late DateTime _month;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
  }

  Map<DateTime, List<UpcomingItem>> get _byDay {
    final map = <DateTime, List<UpcomingItem>>{};
    for (final it in widget.items) {
      final d = it.episode.airDate;
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      map.putIfAbsent(key, () => []).add(it);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _byDay;
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = (first.weekday - 1) % 7; // Monday-first grid
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final selectedItems =
        _selected == null ? const <UpcomingItem>[] : byDay[_selected] ?? [];

    return ListView(
      padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom,
          left: AppSpacing.md,
          right: AppSpacing.md),
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.chevron_left,
                  color: AppColors.textPrimary),
              onPressed: () => setState(() =>
                  _month = DateTime(_month.year, _month.month - 1)),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM().format(_month),
                textAlign: TextAlign.center,
                style: AppTextStyles.rowTitleList,
              ),
            ),
            IconButton(
              icon: Icon(Icons.chevron_right,
                  color: AppColors.textPrimary),
              onPressed: () => setState(() =>
                  _month = DateTime(_month.year, _month.month + 1)),
            ),
          ],
        ),
        Row(
          children: [
            for (final d in const ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'])
              Expanded(
                child: Text(d,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.microCaps),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (var day = 1; day <= daysInMonth; day++)
              _DayCell(
                date: DateTime(_month.year, _month.month, day),
                count: byDay[DateTime(_month.year, _month.month, day)]
                        ?.length ??
                    0,
                isToday:
                    DateTime(_month.year, _month.month, day) == todayKey,
                selected:
                    DateTime(_month.year, _month.month, day) == _selected,
                onTap: () => setState(() => _selected =
                    DateTime(_month.year, _month.month, day)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Divider(height: 1, color: AppColors.divider),
        if (_selected != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              DateFormat.MMMMEEEEd().format(_selected!),
              style: AppTextStyles.captionCaps,
            ),
          ),
          if (selectedItems.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Text('Nothing airing this day.',
                  style: AppTextStyles.subtitle),
            )
          else
            for (final it in selectedItems) UpcomingRow(item: it),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final int count;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;
  const _DayCell({
    required this.date,
    required this.count,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.18)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: AppColors.accent)
                : isToday
                    ? Border.all(color: AppColors.borderSubtle)
                    : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${date.day}',
                  style: AppTextStyles.subtitle.copyWith(
                      color: selected || isToday
                          ? AppColors.textPrimary
                          : AppColors.textSecondary)),
              SizedBox(
                height: 10,
                child: count == 0
                    ? null
                    : count == 1
                        ? Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle),
                          )
                        : Text('$count',
                            style: AppTextStyles.microCaps
                                .copyWith(color: AppColors.accentAlt)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsed shelf of caught-up shows pinned to the top of the watch
/// list — tap to expand and revisit (or swipe-unwatch) finished episodes.
class _CaughtUpSection extends StatefulWidget {
  final List<WatchlistEntry> entries;
  const _CaughtUpSection({required this.entries});
  @override
  State<_CaughtUpSection> createState() => _CaughtUpSectionState();
}

class _CaughtUpSectionState extends State<_CaughtUpSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _open = !_open);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.task_alt,
                    size: 18, color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Text('CAUGHT UP (${widget.entries.length})',
                    style: AppTextStyles.captionCaps
                        .copyWith(color: AppColors.textSecondary)),
                const Spacer(),
                AnimatedRotation(
                  duration: AppMotion.tab,
                  curve: AppMotion.standard,
                  turns: _open ? 0.5 : 0,
                  child: Icon(Icons.keyboard_arrow_down,
                      size: 20, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.slide,
          curve: AppMotion.glide,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  children: [
                    for (final e in widget.entries) EpisodeRow(entry: e),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
        Divider(height: 1, color: AppColors.divider),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
              strokeWidth: 3, color: AppColors.accent),
        ),
      );
}

class _ErrorBody extends StatelessWidget {
  final String error;
  const _ErrorBody({required this.error});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 40, color: AppColors.textPrimary),
              const SizedBox(height: AppSpacing.md),
              Text('Loading failed.', style: AppTextStyles.body),
              const SizedBox(height: AppSpacing.xs),
              Text(error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.subtitle),
            ],
          ),
        ),
      );
}

/// Watch-list row: swipe left to mark the up-next episode watched (red ring
/// + check), swipe right on a watched row to un-watch. Marking watched
/// offers a brief Undo snackbar.
class EpisodeRow extends StatelessWidget {
  final WatchlistEntry entry;
  const EpisodeRow({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final ep = entry.upNext;
    final appState = context.watch<AppState>();
    final watched = ep != null && appState.isWatched(ep.id);
    final row = InkWell(
      onTap: () => context.push('/series/${entry.title.id}'),
      onLongPress: () =>
          showTitleActions(context, title: entry.title, upNext: entry.upNext),
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Poster(
                width: AppLayout.episodeThumb,
                height: AppLayout.episodeThumb,
                imageAsset: ep?.still ??
                    appState.posterOverride(entry.title.id) ??
                    entry.title.poster,
                label: entry.title.name),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShowPill(entry.title.name,
                      onTap: () => context.push('/series/${entry.title.id}')),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Text(ep?.code ?? 'All caught up',
                          style: AppTextStyles.rowTitleList),
                      CountBadge(entry.unwatchedAhead),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(ep?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.subtitle
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            WatchCheck(
              watched: watched,
              onTap: () {
                if (ep != null) context.read<AppState>().toggleWatched(ep.id);
              },
            ),
          ],
        ),
      ),
    );
    if (ep == null) return row;
    // Most recently watched aired episode — the left-to-right swipe target
    // for undoing an accidental mark-watched.
    EpisodeRef? prev;
    for (final s in entry.title.seasons) {
      for (final e in s.episodes) {
        if (appState.isWatched(e.id)) {
          if (prev == null ||
              e.season > prev.season ||
              (e.season == prev.season && e.number > prev.number)) {
            prev = e;
          }
        }
      }
    }
    final prevEp = prev;
    return SwipeToWatch(
      watched: watched,
      previousLabel: prevEp?.code,
      onUndoPrevious: prevEp == null
          ? null
          : () {
              context.read<AppState>().setWatched(prevEp.id, false);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                    backgroundColor: AppColors.surfaceElevated,
                    content: Text(
                      '${entry.title.name} ${prevEp.code} unwatched',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body,
                    ),
                  ),
                );
            },
      onConfirm: () {
        final state = context.read<AppState>();
        final wasWatched = state.isWatched(ep.id);
        state.toggleWatched(ep.id);
        if (!wasWatched) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
                backgroundColor: AppColors.surfaceElevated,
                content: Text(
                  '${entry.title.name} ${ep.code} marked watched',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body,
                ),
                action: SnackBarAction(
                  label: 'UNDO',
                  textColor: AppColors.accentAlt,
                  onPressed: () => state.setWatched(ep.id, false),
                ),
              ),
            );
        }
      },
      child: row,
    );
  }
}

/// An upcoming-episode row with air time or day countdown on the right.
class UpcomingRow extends StatelessWidget {
  final UpcomingItem item;
  const UpcomingRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          Poster(
              width: 88,
              height: 120,
              imageAsset: item.episode.still ?? item.poster,
              label: item.showName),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShowPill(item.showName),
                const SizedBox(height: AppSpacing.sm),
                Text(item.episode.code, style: AppTextStyles.rowTitleList),
                const SizedBox(height: 2),
                Text(item.episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.subtitle),
                if (item.isLatest) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const _Badge('LATEST'),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _RightMeta(item: item),
        ],
      ),
    );
  }
}

class _RightMeta extends StatelessWidget {
  final UpcomingItem item;
  const _RightMeta({required this.item});
  @override
  Widget build(BuildContext context) {
    if (item.daysUntil != null && item.daysUntil! > 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${item.daysUntil}',
              style: AppTextStyles.rowTitle
                  .copyWith(fontSize: 22, fontWeight: FontWeight.w800)),
          Text('DAYS', style: AppTextStyles.microCaps),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(item.airTime ?? 'Today',
            style: AppTextStyles.subtitle
                .copyWith(color: AppColors.textSecondary)),
        if (item.network != null)
          Text(item.network!, style: AppTextStyles.microCaps),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(label,
          style: AppTextStyles.microCaps.copyWith(color: AppColors.bgPrimary)),
    );
  }
}
