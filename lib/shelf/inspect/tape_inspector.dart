import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import '../labels/tape_label_data.dart';
import '../plates/plate_manifest.dart';
import '../shelf_layout.dart';
import '../shelf_renderer.dart';
import '../tape_catalog.dart';
import '../tape_source.dart';
import 'hero_frames.dart';
import 'progress_panel.dart';

/// The modal inspect view: the tapped tape lifts out of the shelf on a
/// spring, turns from its spine to its front cover, and can then be dragged
/// round through the whole rotation. A glass card shows progress and marks
/// the next episode watched.
class TapeInspector {
  TapeInspector._();

  static Future<void> show(
    BuildContext context, {
    required ShelfRenderer renderer,
    required ShelfBay bay,
    required int tape,
    required Rect plateRect,
    required int rowWidthPx,
  }) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: Duration(milliseconds: reduce ? 120 : 320),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, __) => _InspectorPage(
        renderer: renderer,
        bay: bay,
        tape: tape,
        plateRect: plateRect,
        rowWidthPx: rowWidthPx,
      ),
    ));
  }
}

enum _Phase { preparing, lifting, holding, spinning, interactive }

class _InspectorPage extends StatefulWidget {
  const _InspectorPage({
    required this.renderer,
    required this.bay,
    required this.tape,
    required this.plateRect,
    required this.rowWidthPx,
  });

  final ShelfRenderer renderer;
  final ShelfBay bay;
  final int tape;
  final Rect plateRect;
  final int rowWidthPx;

  @override
  State<_InspectorPage> createState() => _InspectorPageState();
}

class _InspectorPageState extends State<_InspectorPage>
    with TickerProviderStateMixin {
  ShelfRenderer get r => widget.renderer;
  String get titleId => widget.bay.tapes[widget.tape].titleId;
  TapeSource get source => r.source;

  HeroFrames? _hero;
  _Phase _phase = _Phase.preparing;
  bool _reduce = false;
  bool _started = false;

  // Lift-out sprite.
  ui.Image? _sprite;
  Rect? _spriteBounds; // opaque part, in plate px
  Size _plateSize = Size.zero;
  late final AnimationController _lift =
      AnimationController.unbounded(vsync: this);
  late final AnimationController _fade = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180));

  // Rotation, in frames (unwrapped).
  double _pos = 0;
  late final AnimationController _spin =
      AnimationController.unbounded(vsync: this);
  int _shownFrame = -1;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  int _dragDir = 1;

  // Geometry (global == local: the route fills the screen).
  Rect _stage = Rect.zero;
  Rect _frameRect = Rect.zero;

  String? _atlasKey;
  Timer? _atlasDebounce;
  Timer? _holdTimeout;
  bool _closing = false;

  HeroGroup? get _group => r.manifest?.hero;

  @override
  void initState() {
    super.initState();
    _lift.addListener(_tickRepaint);
    _fade.addListener(_tickRepaint);
    _spin.addListener(_onSpin);
    source.addListener(_onSource);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      _start();
    }
  }

  void _tickRepaint() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    await r.ready;
    final m = r.manifest, comp = r.compositor;
    if (!mounted || m == null || comp == null) return;
    final hero = HeroFrames(manifest: m, compositor: comp, bundle: r.bundle)
      ..addListener(_onHero);
    setState(() => _hero = hero);
    final g = m.hero;
    _pos = _reduce ? g.nearestAvailable(g.front).toDouble() : 0;
    hero.want(_reduce ? [g.front] : g.path(0, g.front));
    hero.wantFront();
    unawaited(_composeAtlas());
    if (_reduce) {
      setState(() => _phase = _Phase.interactive);
      return;
    }
    // The sprite: this tape's shelf plate and spine art, alone.
    final sprite = await r.tapeSprite(widget.bay, widget.tape, widget.rowWidthPx);
    final draw = widget.bay.drawForTape(widget.tape);
    if (!mounted) {
      sprite?.$1.dispose();
      return;
    }
    if (sprite == null || draw == null) {
      _beginSpin();
      return;
    }
    final bounds = await r.opaqueBounds(draw.plate);
    if (!mounted) {
      sprite.$1.dispose();
      return;
    }
    _sprite = sprite.$1;
    _plateSize = sprite.$2.size;
    _spriteBounds = bounds;
    r.inspecting.value = titleId;
    setState(() => _phase = _Phase.lifting);
    _lift.value = 0;
    await _lift.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 170, damping: 19),
      0,
      1,
      0,
    ));
    if (!mounted) return;
    setState(() => _phase = _Phase.holding);
    _maybeSpin();
    // Never strand the user in the intro: if the frames are slow (or cannot
    // be composited), carry on and let the sprite stand in.
    _holdTimeout = Timer(const Duration(seconds: 3), () {
      if (mounted && _phase == _Phase.holding) _beginSpin();
    });
  }

  Future<void> _composeAtlas() async {
    _atlasKey = source.labelKey(titleId, use: LabelUse.hero);
    // Short patience: print now, and again when artwork arrives.
    final snap = await source.labelData(titleId,
            use: LabelUse.hero, patience: const Duration(milliseconds: 900)) ??
        // Nothing known about the title (offline): print a plain label so
        // the tape still turns, and reprint when the source catches up.
        LabelSnapshot(
            TapeLabelData(
                titleId: titleId,
                title: source.semanticsLabel(titleId),
                state: const TapeState.notStarted()),
            'unknown');
    if (!mounted) {
      snap.dispose();
      return;
    }
    // What is actually printed; a later change of the source's key means
    // something new arrived.
    _atlasKey = snap.key;
    try {
      final atlas = await r.heroPainter(snap.data, 1536);
      final hero = _hero;
      if (!mounted || hero == null) {
        atlas.dispose();
        return;
      }
      hero.setAtlas(atlas);
      final g = _group!;
      if (_phase == _Phase.interactive) {
        _wantAround(_frame);
      } else {
        hero.want(_reduce ? [g.front] : g.path(0, g.front));
      }
    } finally {
      snap.dispose();
    }
  }

  void _onSource() {
    if (!mounted) return;
    setState(() {}); // the card reads titles and states from the source
    if (_hero == null) return;
    final key = source.labelKey(titleId, use: LabelUse.hero);
    if (key == _atlasKey) return;
    _atlasDebounce?.cancel();
    _atlasDebounce = Timer(const Duration(milliseconds: 250), _composeAtlas);
  }

  void _onHero() {
    if (!mounted) return;
    setState(() {});
    if (_phase == _Phase.holding) _maybeSpin();
    if (_phase == _Phase.interactive && !_heroImageMissing) _releaseSprite();
  }

  void _maybeSpin() {
    final hero = _hero;
    final g = _group;
    if (hero == null || g == null) return;
    if (hero.isReady(g.nearestAvailable(0))) {
      _beginSpin();
    } else {
      // Not composited yet (or evicted while the sprite flew): ask again.
      hero.want(g.path(0, g.front));
    }
  }

  void _beginSpin() {
    final g = _group;
    if (g == null || _phase == _Phase.spinning) return;
    setState(() => _phase = _Phase.spinning);
    _fade.forward(from: 0);
    final frames = g.path(0, g.front).length;
    final ms = (frames * 60).clamp(420, 900);
    _spin.value = 0;
    _spin
        .animateTo(1,
            duration: Duration(milliseconds: ms), curve: Curves.easeInOutCubic)
        .whenCompleteOrCancel(() {
      if (!mounted) return;
      _pos = g.front.toDouble();
      setState(() => _phase = _Phase.interactive);
      if (_hero?.nearestReady(g.front) != null) _releaseSprite();
    });
  }

  void _onSpin() {
    final g = _group;
    if (g == null) return;
    if (_phase == _Phase.spinning) {
      _pos = _spin.value * g.front;
    } else if (_phase == _Phase.interactive) {
      _pos = _spin.value;
    }
    _onFrame();
    setState(() {});
  }

  void _releaseSprite() {
    _sprite?.dispose();
    _sprite = null;
  }

  int get _frame {
    final g = _group!;
    return g.nearestAvailable(_pos.round() % g.frames);
  }

  void _onFrame() {
    final f = _frame;
    if (f == _shownFrame) return;
    _shownFrame = f;
    _wantAround(f);
    if (_phase == _Phase.interactive) {
      final now = DateTime.now();
      if (now.difference(_lastTick) > const Duration(milliseconds: 45)) {
        _lastTick = now;
        HapticFeedback.selectionClick();
      }
    }
  }

  void _wantAround(int f) {
    final g = _group;
    final hero = _hero;
    if (g == null || hero == null) return;
    final d = _dragDir;
    // The frame itself, then ahead in the drag direction, then behind.
    hero.want([f, f + d, f + 2 * d, f + 3 * d, f - d, f - 2 * d]);
    if (g.nearestAvailable(f) == g.front) hero.wantFront(urgent: true);
  }

  // ------------------------------------------------------------------
  // Drag to rotate
  // ------------------------------------------------------------------

  double get _pxPerFrame {
    final g = _group;
    if (g == null || _stage.width <= 0) return 16;
    // A drag across the stage turns the tape half way round.
    return math.max(8, _stage.width / (g.frames / 2));
  }

  void _dragStart(DragStartDetails d) {
    if (_phase != _Phase.interactive) return;
    _spin.stop();
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_phase != _Phase.interactive) return;
    if (d.delta.dx != 0) _dragDir = d.delta.dx < 0 ? 1 : -1;
    setState(() => _pos -= d.delta.dx / _pxPerFrame);
    _onFrame();
  }

  void _dragEnd(DragEndDetails d) {
    if (_phase != _Phase.interactive) return;
    final v = -d.velocity.pixelsPerSecond.dx / _pxPerFrame; // frames/s
    _settleTo(_pos + (_reduce ? 0 : v * 0.22), velocity: _reduce ? 0 : v);
  }

  /// Snaps to the available frame nearest [target] (unwrapped frames).
  void _settleTo(double target, {double velocity = 0}) {
    final g = _group!;
    final t = target.round();
    final a = g.nearestAvailable(t % g.frames);
    final end = (t + g.circularDelta(t % g.frames, a)).toDouble();
    if (_reduce) {
      setState(() => _pos = end);
      _onFrame();
      return;
    }
    _spin.value = _pos;
    _spin.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 120, damping: 22),
      _pos,
      end,
      velocity,
    ));
  }

  void _rotateBy(int frames) {
    if (_phase != _Phase.interactive) return;
    _dragDir = frames >= 0 ? 1 : -1;
    _settleTo(_pos + frames);
  }

  // ------------------------------------------------------------------

  void _close() {
    if (_closing) return;
    _closing = true;
    if (!r.isDisposed) r.inspecting.value = null;
    Navigator.of(context).pop();
  }

  void _openDetails() {
    final router = GoRouter.maybeOf(context);
    final path = '/${titleId.startsWith('movie') ? 'movie' : 'series'}/$titleId';
    _close();
    router?.push(path);
  }

  @override
  void dispose() {
    if (!r.isDisposed && r.inspecting.value == titleId) {
      r.inspecting.value = null;
    }
    _atlasDebounce?.cancel();
    _holdTimeout?.cancel();
    source.removeListener(_onSource);
    _lift.dispose();
    _fade.dispose();
    _spin.dispose();
    _hero?.removeListener(_onHero);
    _hero?.dispose();
    _releaseSprite();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Layout
  // ------------------------------------------------------------------

  void _layoutStage(Rect stage, double dpr) {
    _stage = stage;
    final g = _group;
    if (g == null) return;
    // The whole frame (sleeve plus its floor shadow) fits in the stage.
    var k = stage.height * 0.97 / g.size.height;
    k = math.min(k, stage.width * 1.2 / g.size.width);
    final floorY =
        stage.bottom - (g.size.height - g.floorCenterPx.dy) * k - stage.height * 0.01;
    _frameRect = Rect.fromLTWH(
      stage.center.dx - g.floorCenterPx.dx * k,
      floorY - g.floorCenterPx.dy * k,
      g.size.width * k,
      g.size.height * k,
    );
    final hero = _hero;
    if (hero != null) {
      hero.displayHeightPx = _frameRect.height * dpr;
      hero.cassetteWidthPx = 132 * dpr;
    }
  }

  /// The spine of frame 0 on screen: where the lifted sprite lands.
  Rect get _heroSpineRect {
    final g = _group!;
    final k = _frameRect.width / g.size.width;
    final depthPx = 28 / g.mmPerPxAtCenter; // sleeve depth, frame px
    return Rect.fromLTRB(
      _frameRect.left + (g.floorCenterPx.dx - depthPx / 2) * k,
      _frameRect.top + g.topCenterPx.dy * k,
      _frameRect.left + (g.floorCenterPx.dx + depthPx / 2) * k,
      _frameRect.top + g.floorCenterPx.dy * k,
    );
  }

  /// Where the sprite image is drawn for lift progress [t].
  Rect? _spriteRect(double t) {
    final b = _spriteBounds;
    if (b == null || _plateSize.isEmpty) return null;
    final s = widget.plateRect.width / _plateSize.width;
    final start = Rect.fromLTRB(
      widget.plateRect.left + b.left * s,
      widget.plateRect.top + b.top * s,
      widget.plateRect.left + b.right * s,
      widget.plateRect.top + b.bottom * s,
    );
    final end = _heroSpineRect;
    final box = Rect.lerp(start, end, t)!;
    final sx = box.width / b.width, sy = box.height / b.height;
    return Rect.fromLTWH(box.left - b.left * sx, box.top - b.top * sy,
        _plateSize.width * sx, _plateSize.height * sy);
  }

  String _angleLabel() {
    final g = _group;
    if (g == null) return '';
    final f = _frame;
    String near(int target) => g.circularDelta(f, target).abs() <= 1 ? 'x' : '';
    if (near(g.front).isNotEmpty) return 'Front cover';
    if (near(0).isNotEmpty) return 'Spine';
    if (near(g.front * 2).isNotEmpty) return 'Open side, cassette label';
    if (near(g.front * 3).isNotEmpty) return 'Back cover';
    return '${(f * g.stepDeg).round()} degrees';
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final anim = route?.animation ?? kAlwaysCompleteAnimation;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    final size = mq.size;
    final wide = size.width > size.height && size.width >= 640;
    const topBar = 56.0;

    // Stage and panel slots.
    Rect stage;
    if (wide) {
      final panelW = math.min(400.0, size.width * 0.42);
      stage = Rect.fromLTRB(pad.left + AppSpacing.lg, pad.top + topBar,
          size.width - pad.right - panelW - AppSpacing.xl,
          size.height - pad.bottom - AppSpacing.lg);
    } else {
      final h = (size.height - pad.top - topBar - pad.bottom) * 0.56;
      stage = Rect.fromLTWH(pad.left, pad.top + topBar,
          size.width - pad.left - pad.right, math.max(220.0, h));
    }
    _layoutStage(stage, mq.devicePixelRatio);

    final hero = _hero;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !r.isDisposed) r.inspecting.value = null;
      },
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = Curves.easeOut.transform(anim.value);
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                // Dimmed, blurred shelf behind; tap to close.
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _close,
                    child: Semantics(
                      label: 'Close',
                      button: true,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(
                              sigmaX: 14 * t, sigmaY: 14 * t),
                          child: ColoredBox(
                            color: (dark
                                    ? const Color(0xFF000000)
                                    : const Color(0xFFF4F4F6))
                                .withValues(alpha: (dark ? 0.62 : 0.55) * t),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // The tape: sprite while lifting, then the hero frames.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _StagePainter(
                        hero: hero,
                        frame: hero == null ? null : _frame,
                        showFront: _phase == _Phase.interactive &&
                            _group != null &&
                            (_pos - _pos.round()).abs() < 0.01 &&
                            _frame == _group!.front,
                        frameRect: _frameRect,
                        heroOpacity: _heroOpacity * (_closing ? t : 1),
                        sprite: _sprite,
                        spriteRect: _sprite == null ? null : _spriteRect(_lift.value),
                        spriteOpacity: _spriteOpacity,
                        spotlight: dark,
                      ),
                    ),
                  ),
                ),
                // Drag surface over the stage.
                Positioned.fromRect(
                  rect: stage,
                  child: Semantics(
                    label: 'Tape. Drag sideways to turn it.',
                    value: _angleLabel(),
                    increasedValue: 'Turned',
                    decreasedValue: 'Turned',
                    onIncrease: () => _rotateBy((_group?.frames ?? 36) ~/ 4),
                    onDecrease: () => _rotateBy(-(_group?.frames ?? 36) ~/ 4),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: _dragStart,
                      onHorizontalDragUpdate: _dragUpdate,
                      onHorizontalDragEnd: _dragEnd,
                    ),
                  ),
                ),
                // Close button.
                Positioned(
                  top: pad.top + AppSpacing.sm,
                  right: pad.right + AppSpacing.md,
                  child: Opacity(
                    opacity: t,
                    child: GlassSurface(
                      stadium: true,
                      child: IconButton(
                        tooltip: 'Close',
                        icon: Icon(Icons.close, color: AppColors.textPrimary),
                        onPressed: _close,
                      ),
                    ),
                  ),
                ),
                // Progress card.
                _panel(context, stage, wide, size, pad, t),
              ],
            ),
          );
        },
      ),
    );
  }

  double get _heroOpacity => switch (_phase) {
        _Phase.preparing => _reduce ? 1 : 0,
        _Phase.lifting || _Phase.holding => 0,
        _Phase.spinning => _fade.value,
        _Phase.interactive => 1,
      };

  double get _spriteOpacity => switch (_phase) {
        _Phase.lifting || _Phase.holding => 1,
        _ when _heroImageMissing => 1,
        _Phase.spinning => 1 - _fade.value,
        _ => 0,
      };

  /// No rotation frame is ready yet: the lifted sprite stands in for it.
  bool get _heroImageMissing {
    final g = _group;
    return g == null || _hero?.nearestReady(g.front) == null;
  }

  Widget _panel(BuildContext context, Rect stage, bool wide, Size size,
      EdgeInsets pad, double t) {
    final panel = ProgressPanel(
      titleId: titleId,
      source: source,
      cassette: _hero?.cassette,
      onOpenDetails: source is TapeCatalog ? _openDetails : null,
    );
    _wantCassette();
    final slide = Offset(0, (1 - t) * 24);
    final child = Opacity(
      opacity: t,
      child: Transform.translate(offset: slide, child: panel),
    );
    if (wide) {
      final panelW = math.min(400.0, size.width * 0.42);
      return Positioned(
        right: pad.right + AppSpacing.lg,
        top: pad.top + 56,
        bottom: pad.bottom + AppSpacing.lg,
        width: panelW,
        child: Center(child: SingleChildScrollView(child: child)),
      );
    }
    return Positioned(
      left: pad.left + AppSpacing.md,
      right: pad.right + AppSpacing.md,
      top: stage.bottom + AppSpacing.sm,
      bottom: pad.bottom + AppSpacing.md,
      child: SingleChildScrollView(child: child),
    );
  }

  void _wantCassette() {
    final hero = _hero;
    final src = source;
    if (hero == null) return;
    final st = src is TapeCatalog ? src.stateOf(titleId) : null;
    hero.wantCassette(st?.progress ?? 0);
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter({
    required this.hero,
    required this.frame,
    required this.showFront,
    required this.frameRect,
    required this.heroOpacity,
    required this.sprite,
    required this.spriteRect,
    required this.spriteOpacity,
    required this.spotlight,
  });

  final HeroFrames? hero;
  final int? frame;
  final bool showFront;
  final Rect frameRect;
  final double heroOpacity;
  final ui.Image? sprite;
  final Rect? spriteRect;
  final double spriteOpacity;
  final bool spotlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (spotlight && heroOpacity > 0 && !frameRect.isEmpty) {
      // A soft pool of light so the dark sleeve separates from dark glass.
      final c = frameRect.center;
      canvas.drawCircle(
        c,
        frameRect.height * 0.55,
        Paint()
          ..shader = ui.Gradient.radial(c, frameRect.height * 0.55, [
            Color.fromRGBO(255, 255, 255, 0.10 * heroOpacity),
            const Color(0x00FFFFFF),
          ]),
      );
    }
    final h = hero;
    if (h != null && frame != null && heroOpacity > 0) {
      final img = (showFront ? h.front : null) ?? h.frame(frame!) ??
          h.nearestReady(frame!);
      if (img != null) {
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          frameRect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(0, 0, 0, heroOpacity),
        );
      }
    }
    final s = sprite, sr = spriteRect;
    if (s != null && sr != null && spriteOpacity > 0) {
      canvas.drawImageRect(
        s,
        Rect.fromLTWH(0, 0, s.width.toDouble(), s.height.toDouble()),
        sr,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(0, 0, 0, spriteOpacity),
      );
    }
  }

  @override
  bool shouldRepaint(_StagePainter old) => true;
}
