import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Swipe-to-toggle-watched (Task 2).
///
/// Right-to-left on an unwatched row marks it watched — the row slides left
/// revealing a red ring + checkmark that fills toward the threshold.
/// Left-to-right un-watches: on a watched row it un-watches that episode;
/// on an unwatched row it reveals the previously watched episode (label
/// from [previousLabel]) and [onUndoPrevious] un-watches it — the rescue
/// for an accidental mark-watched. Partial swipes spring back; haptics on
/// arming and on confirm.
class SwipeToWatch extends StatefulWidget {
  final Widget child;
  final bool watched;
  final VoidCallback onConfirm;

  /// Episode code of the last watched episode (e.g. "S01 | E03"), shown on
  /// the left-to-right affordance when the row itself isn't watched.
  final String? previousLabel;

  /// Un-watches the previously watched episode. Enables the left-to-right
  /// swipe on unwatched rows.
  final VoidCallback? onUndoPrevious;

  const SwipeToWatch({
    super.key,
    required this.child,
    required this.watched,
    required this.onConfirm,
    this.previousLabel,
    this.onUndoPrevious,
  });

  @override
  State<SwipeToWatch> createState() => _SwipeToWatchState();
}

class _SwipeToWatchState extends State<SwipeToWatch>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  bool _armed = false;
  late final AnimationController _spring;

  static const double _threshold = 96;

  bool get _allowLeft => !widget.watched;
  bool get _allowRight => widget.watched || widget.onUndoPrevious != null;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
  }

  void _update(DragUpdateDetails d) {
    setState(() {
      _drag = (_drag + d.delta.dx).clamp(
        _allowLeft ? -_threshold * 1.4 : 0.0,
        _allowRight ? _threshold * 1.4 : 0.0,
      );
      final nowArmed = _drag.abs() >= _threshold;
      if (nowArmed && !_armed) HapticFeedback.lightImpact();
      _armed = nowArmed;
    });
  }

  void _end(DragEndDetails d) {
    if (_drag <= -_threshold) {
      HapticFeedback.mediumImpact();
      widget.onConfirm();
    } else if (_drag >= _threshold) {
      HapticFeedback.mediumImpact();
      if (widget.watched) {
        widget.onConfirm();
      } else {
        widget.onUndoPrevious?.call();
      }
    }
    _armed = false;
    final start = _drag;
    _spring
      ..reset()
      ..addListener(() {
        setState(() {
          _drag = start * (1 - AppMotion.pop.transform(_spring.value));
        });
      })
      ..forward();
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_drag.abs() / _threshold).clamp(0.0, 1.0);
    final rightward = _drag > 0;
    final undo = rightward; // both rightward actions are "un-watch"
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: Color.lerp(Colors.transparent,
                  AppColors.love.withValues(alpha: 0.16), progress),
              alignment:
                  rightward ? Alignment.centerLeft : Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RingCheck(progress: progress, armed: _armed, undo: undo),
                  if (undo &&
                      !widget.watched &&
                      widget.previousLabel != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    Opacity(
                      opacity: progress,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('UNWATCH',
                              style: AppTextStyles.microCaps
                                  .copyWith(color: AppColors.love)),
                          Text(widget.previousLabel!,
                              style: AppTextStyles.rowTitleList),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_drag, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// TV Time-style red ring: outline circle whose glyph scales in with drag
/// progress; when armed (past threshold) the ring fills solid red.
class _RingCheck extends StatelessWidget {
  final double progress;
  final bool armed;
  final bool undo;
  const _RingCheck({
    required this.progress,
    required this.armed,
    required this.undo,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      width: AppLayout.checkCircle,
      height: AppLayout.checkCircle,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: armed ? AppColors.love : Colors.transparent,
        border: Border.all(color: AppColors.love, width: 3),
        boxShadow: armed
            ? [
                BoxShadow(
                    color: AppColors.love.withValues(alpha: 0.5),
                    blurRadius: 14),
              ]
            : const [],
      ),
      child: Transform.scale(
        scale: 0.4 + progress * 0.6,
        child: Opacity(
          opacity: progress,
          child: Icon(
            undo ? Icons.undo : Icons.check,
            color: armed ? Colors.white : AppColors.love,
            size: 24,
          ),
        ),
      ),
    );
  }
}
