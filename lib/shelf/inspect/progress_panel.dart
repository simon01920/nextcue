import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import '../labels/tape_label_data.dart';
import '../tape_catalog.dart';
import '../tape_source.dart';

/// The inspect view's glass card: the cassette wound to the title's
/// progress, where the user is, and a one-tap "mark watched" for the next
/// episode — the same episode (and the same [AppState] call) as the watch
/// list's swipe-to-watch.
class ProgressPanel extends StatefulWidget {
  const ProgressPanel({
    super.key,
    required this.titleId,
    required this.source,
    required this.cassette,
    this.onOpenDetails,
  });

  final String titleId;
  final TapeSource source;

  /// The composited cassette plate (null while it composes).
  final ui.Image? cassette;
  final VoidCallback? onOpenDetails;

  @override
  State<ProgressPanel> createState() => _ProgressPanelState();
}

class _ProgressPanelState extends State<ProgressPanel> {
  String? _done;
  VoidCallback? _undo;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  void _offerUndo(String message, VoidCallback undo) {
    _undoTimer?.cancel();
    setState(() {
      _done = message;
      _undo = undo;
    });
    _undoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _undo = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final source = widget.source;
    final catalog = source is TapeCatalog ? source : null;
    final title = catalog?.title(widget.titleId);
    final state = catalog?.stateOf(widget.titleId);
    final isMovie = title?.kind == MediaKind.movie ||
        widget.titleId.startsWith('movie');
    // A title marked completed is done, even if its episodes were never
    // ticked one by one.
    final next =
        title == null || isMovie || state?.kind == TapeStateKind.completed
            ? null
            : TapeStates.nextEpisode(title, appState);
    final scheme = Theme.of(context).colorScheme;

    final name = title?.name ?? source.semanticsLabel(widget.titleId);
    final meta = [
      if (title != null && title.yearLine.isNotEmpty) title.yearLine,
      isMovie ? 'Movie' : 'Show',
    ].join(' · ');

    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.rowTitle),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(meta, style: AppTextStyles.subtitle),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _Cassette(image: widget.cassette),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _StateLine(state: state, isMovie: isMovie),
          if (state != null && !isMovie && state.total > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: state.progress.clamp(0.0, 1.0),
                minHeight: 6,
                color: AppColors.accent,
                backgroundColor: AppColors.textMuted.withValues(alpha: 0.25),
                semanticsLabel:
                    'Watched ${state.watched} of ${state.total} episodes',
              ),
            ),
          ],
          if (next != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text('UP NEXT', style: AppTextStyles.microCaps),
            const SizedBox(height: AppSpacing.xxs),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: TapeStates.code(next),
                    style: AppTextStyles.rowTitleList),
                if (next.title.isNotEmpty)
                  TextSpan(
                      text: '  ${next.title}',
                      style: AppTextStyles.subtitle
                          .copyWith(color: AppColors.textSecondary)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_undo != null && _done != null)
            _UndoRow(
              message: _done!,
              onUndo: () {
                HapticFeedback.selectionClick();
                _undo?.call();
                _undoTimer?.cancel();
                setState(() => _undo = null);
              },
            )
          else if (next != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.accentInk,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: Text('Mark ${TapeStates.code(next)} watched',
                  style: AppTextStyles.buttonPillCaps),
              onPressed: () {
                HapticFeedback.mediumImpact();
                final id = next.id;
                appState.setWatched(id, true);
                _offerUndo('${TapeStates.code(next)} marked watched',
                    () => appState.setWatched(id, false));
              },
            )
          else if (isMovie &&
              appState.statusOf(widget.titleId) != TrackStatus.completed)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.accentInk,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: Text('Mark watched', style: AppTextStyles.buttonPillCaps),
              onPressed: () {
                HapticFeedback.mediumImpact();
                final before = appState.statusOf(widget.titleId);
                // A movie has no episodes: watched is the completed status,
                // as on the Movies screen.
                appState.setStatus(widget.titleId, TrackStatus.completed);
                _offerUndo('Marked watched',
                    () => appState.setStatus(widget.titleId, before));
              },
            )
          else
            Text(
              state?.kind == TapeStateKind.completed || isMovie
                  ? 'Watched. Be kind, rewind.'
                  : 'All caught up.',
              style: AppTextStyles.subtitle
                  .copyWith(color: AppColors.textSecondary),
            ),
          if (widget.onOpenDetails != null) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: widget.onOpenDetails,
              style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
              child: Text('OPEN DETAILS',
                  style: AppTextStyles.buttonPillCaps
                      .copyWith(color: AppColors.textPrimary)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StateLine extends StatelessWidget {
  const _StateLine({required this.state, required this.isMovie});

  final TapeState? state;
  final bool isMovie;

  @override
  Widget build(BuildContext context) {
    final st = state;
    if (st == null) {
      return Text('Loading…', style: AppTextStyles.subtitle);
    }
    final (label, color) = switch (st.kind) {
      TapeStateKind.notStarted => ('NOT STARTED', AppColors.textSecondary),
      TapeStateKind.watching => ('WATCHING', AppColors.accent),
      TapeStateKind.newEpisode => ('NEW EPISODE', AppColors.accent),
      TapeStateKind.completed => ('COMPLETED', AppColors.success),
    };
    final detail = !isMovie && st.total > 0
        ? '${st.watched} of ${st.total} episodes'
        : null;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
          decoration: BoxDecoration(
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Text(label, style: AppTextStyles.microCaps.copyWith(color: color)),
        ),
        if (detail != null)
          Text(detail,
              style: AppTextStyles.subtitle
                  .copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _UndoRow extends StatelessWidget {
  const _UndoRow({required this.message, required this.onUndo});

  final String message;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(message,
              style: AppTextStyles.body.copyWith(height: 1.3)),
        ),
        TextButton(
          onPressed: onUndo,
          child: Text('UNDO',
              style: AppTextStyles.buttonPillCaps
                  .copyWith(color: AppColors.accentAlt)),
        ),
      ],
    );
  }
}

/// The cassette plate, face up (900 × 620 framing).
class _Cassette extends StatelessWidget {
  const _Cassette({required this.image});

  final ui.Image? image;

  static const double width = 132;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 620 / 900,
      child: image == null
          ? const SizedBox.shrink()
          : CustomPaint(painter: _ImagePainter(image!)),
    );
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter old) => old.image != image;
}
