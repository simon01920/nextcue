import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/top_tabs.dart';

/// Stats — real numbers derived from the account's tracked state, plus
/// simple single-hue bar charts (most-watched shows, library breakdown).
/// Time estimates: 24 min per episode, 110 min per movie.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: ContentColumn(
        child: Column(
          children: [
            TopTabs(
              labels: const ['SHOWS', 'MOVIES'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            Expanded(
              child: _tab == 0
                  ? _ShowsStats(appState: appState)
                  : _MoviesStats(appState: appState),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowsStats extends StatelessWidget {
  final AppState appState;
  const _ShowsStats({required this.appState});

  @override
  Widget build(BuildContext context) {
    final episodes = appState.watchedEpisodeTotal;
    final trackedShows =
        appState.trackedIds.where((i) => i.startsWith('series')).toList();
    final byShow = [
      for (final id in trackedShows) (id, appState.watchedCountFor(id)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final top = byShow.where((e) => e.$2 > 0).take(6).toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _BigStat(
          title: 'Time spent watching episodes',
          units: _timeUnits(episodes * 24),
        ),
        _BigStatSingle(
          title: 'Total episodes watched',
          value: '$episodes',
          footnote: 'ACROSS ${byShow.where((e) => e.$2 > 0).length} SHOWS',
        ),
        if (top.isNotEmpty)
          _ChartCard(
            title: 'Most watched shows',
            child: _TitleBarChart(rows: top),
          ),
        _ChartCard(
          title: 'Shows by status',
          child: _StatusBarChart(appState: appState, prefix: 'series'),
        ),
        _BigStatSingle(
          title: 'Added shows',
          value: '${trackedShows.length}',
          footnote: 'IN YOUR LIBRARY',
        ),
      ],
    );
  }
}

class _MoviesStats extends StatelessWidget {
  final AppState appState;
  const _MoviesStats({required this.appState});

  @override
  Widget build(BuildContext context) {
    final trackedMovies =
        appState.trackedIds.where((i) => i.startsWith('movie')).toList();
    final watched = appState
        .idsWithStatus(TrackStatus.completed)
        .where((i) => i.startsWith('movie'))
        .length;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _BigStat(
          title: 'Time spent watching movies',
          units: _timeUnits(watched * 110),
        ),
        _BigStatSingle(
          title: 'Movies watched',
          value: '$watched',
          footnote: 'OF ${trackedMovies.length} IN YOUR LIBRARY',
        ),
        _ChartCard(
          title: 'Movies by status',
          child: _StatusBarChart(appState: appState, prefix: 'movie'),
        ),
      ],
    );
  }
}

List<StatUnit> _timeUnits(int minutes) {
  final months = minutes ~/ (60 * 24 * 30);
  final days = (minutes ~/ (60 * 24)) % 30;
  final hours = (minutes ~/ 60) % 24;
  return [
    StatUnit('$months', 'months'),
    StatUnit('$days', 'days'),
    StatUnit('$hours', 'hours'),
  ];
}

// ---------------------------------------------------------------------------
// Charts — single-hue horizontal bars: thin marks, rounded data end, flat
// baseline, labels/values in text tokens (identity comes from row labels,
// so no legend is needed).
// ---------------------------------------------------------------------------

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return _StatCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTextStyles.sectionHeader.copyWith(fontSize: 20)),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  const _BarRow({required this.label, required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.subtitle
                        .copyWith(color: AppColors.textSecondary)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('$value',
                  style: AppTextStyles.subtitle.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 12,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: t.clamp(0.0, 1.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Top shows by watched-episode count; names resolved from the repository.
class _TitleBarChart extends StatelessWidget {
  final List<(String, int)> rows;
  const _TitleBarChart({required this.rows});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final max = rows.first.$2;
    return Column(
      children: [
        for (final (id, count) in rows)
          FutureBuilder<MediaTitle>(
            future: repo.titleById(id),
            builder: (context, snap) => _BarRow(
              label: snap.data?.name ?? '…',
              value: count,
              max: max,
            ),
          ),
      ],
    );
  }
}

class _StatusBarChart extends StatelessWidget {
  final AppState appState;
  final String prefix;
  const _StatusBarChart({required this.appState, required this.prefix});

  static const _labels = {
    TrackStatus.watching: 'Watching',
    TrackStatus.planToWatch: 'Plan to watch',
    TrackStatus.completed: 'Completed',
    TrackStatus.stopped: 'Stopped',
  };

  @override
  Widget build(BuildContext context) {
    final counts = [
      for (final s in TrackStatus.values)
        (
          _labels[s]!,
          appState
              .idsWithStatus(s)
              .where((i) => i.startsWith(prefix))
              .length,
        ),
    ];
    final max = counts.fold<int>(0, (m, c) => c.$2 > m ? c.$2 : m);
    if (max == 0) {
      return Text('Nothing tracked yet.',
          style: AppTextStyles.subtitle);
    }
    return Column(
      children: [
        for (final (label, value) in counts)
          _BarRow(label: label, value: value, max: max),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero stat cards
// ---------------------------------------------------------------------------

class _StatCardShell extends StatelessWidget {
  final Widget child;
  const _StatCardShell({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: child,
    );
  }
}

class _BigStat extends StatelessWidget {
  final String title;
  final List<StatUnit> units;
  const _BigStat({required this.title, required this.units});
  @override
  Widget build(BuildContext context) {
    return _StatCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTextStyles.sectionHeader.copyWith(fontSize: 20)),
          const SizedBox(height: AppSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                for (final u in units) ...[
                  Text(u.number,
                      style:
                          AppTextStyles.sectionHeader.copyWith(fontSize: 34)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(u.unit, style: AppTextStyles.subtitle),
                  const SizedBox(width: AppSpacing.md),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BigStatSingle extends StatelessWidget {
  final String title;
  final String value;
  final String footnote;
  const _BigStatSingle(
      {required this.title, required this.value, required this.footnote});
  @override
  Widget build(BuildContext context) {
    return _StatCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTextStyles.sectionHeader.copyWith(fontSize: 20)),
          const SizedBox(height: AppSpacing.md),
          Text(value,
              style: AppTextStyles.sectionHeader.copyWith(fontSize: 34)),
          const SizedBox(height: AppSpacing.xs),
          Text(footnote, style: AppTextStyles.captionCaps),
        ],
      ),
    );
  }
}
