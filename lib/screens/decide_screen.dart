import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Image, Gradient;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/poster.dart';

/// "Decide" (Task 3) — picks what to watch next from the shows watch list.
/// Exactly 2 shows: poster coin flip. 3–8: glass roulette wheel with poster
/// segments. 9+: sliding reel chooser. The Discover entry button is
/// disabled below 2 shows, so those modes never open.
class DecideScreen extends StatefulWidget {
  const DecideScreen({super.key});

  @override
  State<DecideScreen> createState() => _DecideScreenState();
}

class _DecideScreenState extends State<DecideScreen> {
  Future<List<WatchlistEntry>>? _future;
  WatchlistEntry? _result;
  int _round = 0;

  /// Shows with an episode ready to watch. Caught-up shows only join in
  /// when fewer than two are ready, so the wheel never picks a show with
  /// nothing to play.
  static List<WatchlistEntry> _candidates(List<WatchlistEntry> all) {
    final ready = all.where((e) => e.upNext != null).toList();
    return ready.length >= 2 ? ready : all;
  }

  @override
  Widget build(BuildContext context) {
    _future ??= context.read<ContentRepository>().showWatchlist();
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<WatchlistEntry>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: AppColors.accent),
                ),
              );
            }
            final entries = _candidates(snap.data!);
            final titles = entries.map((e) => e.title).toList();
            return Stack(
              children: [
                Column(
                  children: [
                    _Header(onClose: () => context.pop()),
                    Expanded(child: _mode(entries)),
                  ],
                ),
                if (_result != null)
                  _ResultOverlay(
                    key: ValueKey('result$_round'),
                    entry: _result!,
                    again: titles.length == 2
                        ? 'FLIP AGAIN'
                        : titles.length <= 8
                            ? 'SPIN AGAIN'
                            : 'ROLL AGAIN',
                    onWatch: () {
                      final t = _result!.title;
                      context.pushReplacement(
                          '/${t.kind == MediaKind.movie ? 'movie' : 'series'}/${t.id}');
                    },
                    onAgain: () => setState(() {
                      _result = null;
                      _round++;
                    }),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _mode(List<WatchlistEntry> entries) {
    final titles = entries.map((e) => e.title).toList();
    void done(MediaTitle t) => setState(
        () => _result = entries.firstWhere((e) => identical(e.title, t)));
    if (titles.length < 2) {
      return Center(
        child: Text(
          'Add at least 2 shows to your\nwatch list to decide.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body,
        ),
      );
    }
    if (titles.length == 2) {
      return _CoinDecider(
          key: ValueKey('coin$_round'), titles: titles, onDone: done);
    }
    if (titles.length <= 8) {
      return _WheelDecider(
          key: ValueKey('wheel$_round'), titles: titles, onDone: done);
    }
    return _ReelDecider(
        key: ValueKey('reel$_round'), titles: titles, onDone: done);
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close,
                color: AppColors.textPrimary, size: 26),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('Decide', style: AppTextStyles.screenTitle),
        ],
      ),
    );
  }
}

/// Resolves a network poster into a raw [ui.Image] for canvas painting.
Future<ui.Image?> _loadUiImage(String? url, {int? width}) {
  if (url == null || !url.startsWith('http')) return Future.value(null);
  final completer = Completer<ui.Image?>();
  final ImageProvider provider = width == null
      ? NetworkImage(url)
      : ResizeImage(NetworkImage(url),
          width: width, policy: ResizeImagePolicy.fit);
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      // Clone: the stream's handle is released with the cache entry, and
      // painting a disposed image throws. The caller owns (and disposes)
      // the clone.
      if (!completer.isCompleted) completer.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (e, s) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

// ---------------------------------------------------------------------------
// Wheel mode (3–8 shows)
// ---------------------------------------------------------------------------

class _WheelDecider extends StatefulWidget {
  final List<MediaTitle> titles;
  final ValueChanged<MediaTitle> onDone;
  const _WheelDecider({super.key, required this.titles, required this.onDone});

  @override
  State<_WheelDecider> createState() => _WheelDeciderState();
}

class _WheelDeciderState extends State<_WheelDecider>
    with TickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  late final AnimationController _glowCtrl;
  late final List<ui.Image?> _posters;
  late final List<String> _labels;
  final _random = math.Random();

  /// Wheel rotation in radians. Kept continuous across spins and drags so
  /// the wheel never snaps back to zero.
  double _angle = 0;
  double _from = 0, _to = 0;
  int? _chosen;
  bool _spinning = false;

  // Drag-to-spin.
  double? _dragAngle;
  final List<(Duration, double)> _dragSamples = [];

  // Ticker pointer: a flap kick each time a segment boundary passes under it.
  int _lastSegment = 0;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  final ValueNotifier<double> _flap = ValueNotifier(0);

  double get _sweep => 2 * math.pi / widget.titles.length;

  @override
  void initState() {
    super.initState();
    _labels = widget.titles.map((t) => t.name).toList(growable: false);
    _spinCtrl = AnimationController(vsync: this)..addListener(_onSpinFrame);
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _posters = List.filled(widget.titles.length, null);
    for (var i = 0; i < widget.titles.length; i++) {
      // Decoded at wheel size, not the full ~680x1000 poster.
      _loadUiImage(widget.titles[i].poster, width: 360).then((img) {
        if (img == null) return;
        if (!mounted) {
          img.dispose();
          return;
        }
        setState(() => _posters[i] = img);
      });
    }
  }

  /// Segment index under the top pointer for wheel rotation [a].
  int _segmentAt(double a) {
    final n = widget.titles.length;
    final t = (-a) % (2 * math.pi);
    return (t / _sweep).floor() % n;
  }

  void _setAngle(double a) {
    _angle = a;
    final seg = _segmentAt(a);
    if (seg != _lastSegment) {
      _lastSegment = seg;
      final now = DateTime.now();
      // Haptic tick per segment, rate-limited so a fast spin buzzes rather
      // than stutters.
      if (now.difference(_lastTick) > const Duration(milliseconds: 45)) {
        HapticFeedback.selectionClick();
        _lastTick = now;
      }
      _flap.value = 1;
    } else {
      _flap.value = math.max(0, _flap.value - 0.18);
    }
  }

  void _onSpinFrame() {
    final t = _curve.transform(_spinCtrl.value);
    setState(() => _setAngle(_from + (_to - _from) * t));
  }

  // Fast start, long smooth deceleration, tiny settle at the end.
  static const Curve _curve = Cubic(0.12, 0.72, 0.18, 1.0);

  void _spin({double velocity = 0}) {
    if (_spinning) return;
    final n = widget.titles.length;
    final i = _random.nextInt(n);
    // Land somewhere inside the segment, not dead centre every time
    // (which reads as rigged).
    final f = 0.18 + _random.nextDouble() * 0.64;
    final desired = (-(i + f) * _sweep) % (2 * math.pi);
    final current = _angle % (2 * math.pi);
    var delta = (desired - current) % (2 * math.pi);
    // A harder flick spins more turns.
    final turns = 4 + (velocity.abs() / 6).clamp(0, 3).round();
    delta += turns * 2 * math.pi;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _from = _angle;
    _to = _angle + delta;
    _spinCtrl.duration = reduceMotion
        ? const Duration(milliseconds: 900)
        : Duration(milliseconds: 4200 + turns * 150);
    setState(() {
      _chosen = i;
      _spinning = true;
    });
    HapticFeedback.mediumImpact();
    _spinCtrl.forward(from: 0).whenComplete(() async {
      if (!mounted) return;
      _flap.value = 0;
      HapticFeedback.heavyImpact();
      _glowCtrl.repeat(reverse: true);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      _glowCtrl.stop();
      widget.onDone(widget.titles[i]);
    });
  }

  double _angleOf(Offset local, Size size) =>
      math.atan2(local.dy - size.height / 2, local.dx - size.width / 2);

  void _onPanStart(DragStartDetails d, Size size) {
    if (_spinning) return;
    _dragAngle = _angleOf(d.localPosition, size);
    _dragSamples.clear();
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    if (_spinning || _dragAngle == null) return;
    final a = _angleOf(d.localPosition, size);
    var da = a - _dragAngle!;
    if (da > math.pi) da -= 2 * math.pi;
    if (da < -math.pi) da += 2 * math.pi;
    _dragAngle = a;
    _dragSamples.add((d.sourceTimeStamp ?? Duration.zero, da));
    if (_dragSamples.length > 6) _dragSamples.removeAt(0);
    setState(() => _setAngle(_angle + da));
  }

  void _onPanEnd(DragEndDetails d) {
    if (_spinning || _dragAngle == null) return;
    _dragAngle = null;
    // Angular velocity from the last few samples (rad/s).
    double v = 0;
    if (_dragSamples.length >= 2) {
      final dt = (_dragSamples.last.$1 - _dragSamples.first.$1).inMicroseconds /
          1e6;
      final sum = _dragSamples.fold<double>(0, (s, e) => s + e.$2);
      if (dt > 0) v = sum / dt;
    }
    if (v.abs() > 3) _spin(velocity: v);
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _glowCtrl.dispose();
    _flap.dispose();
    for (final p in _posters) {
      p?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = math.min(
            math.min(box.maxWidth - AppSpacing.xl * 2, box.maxHeight - 170),
            400.0);
        final wheelSize = Size.square(size - 8);
        final landed = _spinning && _spinCtrl.isCompleted;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _spinning
                  ? (landed ? 'AND THE PICK IS…' : 'SPINNING…')
                  : 'FLICK THE WHEEL OR TAP SPIN',
              style: AppTextStyles.captionCaps,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: size + 28,
              height: size + 28,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _GlassCircle(diameter: size + 28),
                  // Rim studs, like a fairground wheel.
                  IgnorePointer(
                    child: CustomPaint(
                      size: Size.square(size + 28),
                      painter: _RimPainter(count: widget.titles.length * 3),
                    ),
                  ),
                  GestureDetector(
                    onPanStart: (d) => _onPanStart(d, wheelSize),
                    onPanUpdate: (d) => _onPanUpdate(d, wheelSize),
                    onPanEnd: _onPanEnd,
                    child: Transform.rotate(
                      angle: _angle,
                      // The wheel art is painted once and cached as a layer;
                      // spinning only rotates it.
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _glowCtrl,
                          builder: (context, _) => CustomPaint(
                            size: wheelSize,
                            painter: _WheelPainter(
                              labels: _labels,
                              posters: List.unmodifiable(_posters),
                              highlight: landed ? _chosen : null,
                              glow: landed ? _glowCtrl.value : 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Hub doubles as a spin button.
                  GestureDetector(
                    onTap: _spinning ? null : () => _spin(),
                    child: _GlassCircle(
                      diameter: size * 0.22,
                      child: Icon(Icons.casino,
                          color: _spinning
                              ? AppColors.textDisabled
                              : AppColors.accentAlt,
                          size: 26),
                    ),
                  ),
                  Positioned(
                    top: -10,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _flap,
                      builder: (context, flap, child) => Transform.rotate(
                        // Kicks against the direction of travel, springs back.
                        angle: -0.45 * flap,
                        alignment: const Alignment(0, -0.6),
                        child: child,
                      ),
                      child: CustomPaint(
                        size: const Size(30, 38),
                        painter: _PointerPainter(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: 220,
              child: BrandButton(
                label: _spinning ? 'SPINNING…' : 'SPIN',
                onTap: _spinning ? null : () => _spin(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Poster-art segments under a scrim so the wrapped 2-line labels stay
/// readable; alternating red/smoked fills while artwork loads. Labels are
/// laid out once per size, not per frame.
class _WheelPainter extends CustomPainter {
  final List<String> labels;
  final List<ui.Image?> posters;
  final int? highlight;
  final double glow;
  _WheelPainter({
    required this.labels,
    required this.posters,
    this.highlight,
    this.glow = 0,
  });

  static const _reds = [AppColors.accent, Color(0xFF8F0008)];

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    final sweep = 2 * math.pi / n;
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * sweep;
      final sector = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, start, sweep, false)
        ..close();
      final img = i < posters.length ? posters[i] : null;
      final dim = highlight != null && highlight != i;
      canvas.save();
      canvas.clipPath(sector);
      if (img != null) {
        // Cover the sector with the poster, centred along the segment's
        // bisector so the art's subject sits in the slice.
        final mid = start + sweep / 2;
        final c = center + Offset(math.cos(mid), math.sin(mid)) * radius * 0.55;
        final box = radius * (n <= 4 ? 1.3 : 1.0);
        final scale = math.max(box / img.width, box / img.height);
        final dst = Rect.fromCenter(
            center: c, width: img.width * scale, height: img.height * scale);
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          dst,
          Paint()..filterQuality = FilterQuality.medium,
        );
        // Radial scrim: darker toward the rim where the label sits.
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.radial(center, radius, const [
              Color(0x33000000),
              Color(0x99000000),
            ]),
        );
      } else {
        final fill = i.isEven
            ? _reds[(i ~/ 2).isEven ? 0 : 1]
            : AppColors.surfaceElevated;
        canvas.drawPath(sector, Paint()..color = fill);
      }
      if (dim) {
        canvas.drawRect(rect, Paint()..color = const Color(0x8C000000));
      }
      canvas.restore();
      // Segment dividers.
      final edge = center + Offset(math.cos(start), math.sin(start)) * radius;
      canvas.drawLine(
          center,
          edge,
          Paint()
            ..strokeWidth = 2
            ..color = const Color(0x59FFFFFF));
    }

    if (highlight != null) {
      final start = -math.pi / 2 + highlight! * sweep;
      canvas.drawArc(
        rect.deflate(2),
        start,
        sweep,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 + 3 * glow
          ..color = Color.lerp(Colors.white70, Colors.white, glow)!
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 6 * glow),
      );
    }

    // Outer rim line.
    canvas.drawCircle(
        center,
        radius - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x66FFFFFF));

    // Radial labels, two lines max, reading outward from the hub.
    final labelWidth = radius * 0.56;
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * sweep + sweep / 2;
      final tp = _label(labels[i], n, labelWidth);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      tp.paint(canvas, Offset(radius * 0.30, -tp.height / 2));
      canvas.restore();
    }
  }

  static final Map<String, TextPainter> _labelCache = {};

  static TextPainter _label(String text, int n, double width) {
    final key = '$text|$n|${width.round()}';
    return _labelCache[key] ??= TextPainter(
      text: TextSpan(
        text: text.toUpperCase(),
        style: AppTextStyles.microCaps.copyWith(
          color: Colors.white,
          fontSize: n > 6 ? 10 : 11.5,
          letterSpacing: 0.4,
          height: 1.2,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4)],
        ),
      ),
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.highlight != highlight ||
      old.glow != glow ||
      !_sameImages(old.posters, posters) ||
      !identical(old.labels, labels);

  static bool _sameImages(List<ui.Image?> a, List<ui.Image?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

/// Small lamp studs around the rim.
class _RimPainter extends CustomPainter {
  final int count;
  _RimPainter({required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 7;
    for (var i = 0; i < count; i++) {
      final a = 2 * math.pi * i / count;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(
          p,
          2.4,
          Paint()
            ..color = i.isEven ? const Color(0xE6FFFFFF) : const Color(0x80FF3B30)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1));
    }
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.count != count;
}

/// Ticker flap: a rounded red pointer with a white pin.
class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h)
      ..cubicTo(w * 0.2, h * 0.62, 0, h * 0.42, 0, h * 0.3)
      ..arcToPoint(Offset(w, h * 0.3), radius: Radius.circular(w / 2))
      ..cubicTo(w, h * 0.42, w * 0.8, h * 0.62, w * 0.5, h)
      ..close();
    canvas.drawShadow(path, Colors.black, 4, false);
    canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), const [
            Color(0xFFFF4D45),
            AppColors.love,
          ]));
    canvas.drawCircle(Offset(w / 2, h * 0.3), w * 0.16,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => false;
}

// ---------------------------------------------------------------------------
// Reel mode (9+ shows) — a sliding roulette strip that decelerates onto the
// winner under a fixed center frame.
// ---------------------------------------------------------------------------

class _ReelDecider extends StatefulWidget {
  final List<MediaTitle> titles;
  final ValueChanged<MediaTitle> onDone;
  const _ReelDecider({super.key, required this.titles, required this.onDone});

  @override
  State<_ReelDecider> createState() => _ReelDeciderState();
}

class _ReelDeciderState extends State<_ReelDecider> {
  static const double _extent = 136;
  static const double _cardW = 124;
  static const double _cardH = 180;
  static const int _loops = 8;

  late final ScrollController _scroll;
  double _viewportW = 0;
  int? _landedIndex; // index into the repeated strip
  bool _spinning = false;

  int get _n => widget.titles.length;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(initialScrollOffset: _n * 2 * _extent)
      ..addListener(_tick);
  }

  int _lastCard = -1;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// A haptic tick as each card crosses the centre frame (rate-limited so
  /// the fast start buzzes and the slow finish clicks).
  void _tick() {
    if (!_spinning || _viewportW == 0) return;
    final card = ((_scroll.offset + _viewportW / 2) / _extent).floor();
    if (card == _lastCard) return;
    _lastCard = card;
    final now = DateTime.now();
    if (now.difference(_lastTick) > const Duration(milliseconds: 45)) {
      HapticFeedback.selectionClick();
      _lastTick = now;
    }
  }

  Future<void> _spin() async {
    if (_spinning || _viewportW == 0) return;
    final chosen = math.Random().nextInt(_n);
    final targetIndex = _n * (_loops - 2) + chosen;
    final target =
        targetIndex * _extent + _extent / 2 - _viewportW / 2;
    setState(() {
      _spinning = true;
      _landedIndex = null;
    });
    HapticFeedback.selectionClick();
    await _scroll.animateTo(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 4200),
      curve: const Cubic(0.12, 0.72, 0.18, 1.0),
    );
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() => _landedIndex = targetIndex);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) widget.onDone(widget.titles[chosen]);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$_n SHOWS IN THE DRUM',
            style: AppTextStyles.captionCaps),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          height: _cardH + 24,
          child: LayoutBuilder(
            builder: (context, box) {
              _viewportW = box.maxWidth;
              return Stack(
                children: [
                  ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemExtent: _extent,
                    itemCount: _n * _loops,
                    itemBuilder: (context, i) => Center(
                      child: _ReelCard(
                        title: widget.titles[i % _n],
                        width: _cardW,
                        height: _cardH,
                        landed: _landedIndex == i,
                      ),
                    ),
                  ),
                  // Edge fades so the strip reads as a drum.
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          stops: const [0, 0.12, 0.88, 1],
                          colors: [
                            AppColors.bgPrimary,
                            Colors.transparent,
                            Colors.transparent,
                            AppColors.bgPrimary,
                          ],
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // Fixed center frame the winner lands under.
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: _cardW + 12,
                        height: _cardH + 16,
                        decoration: ShapeDecoration(
                          shape: ContinuousRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                            side: const BorderSide(
                                color: AppColors.accentAlt, width: 2),
                          ),
                          shadows: [
                            BoxShadow(
                              color:
                                  AppColors.accent.withValues(alpha: 0.35),
                              blurRadius: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        SizedBox(
          width: 220,
          child: BrandButton(
            label: _spinning ? 'ROLLING…' : 'ROLL',
            onTap: _spinning ? null : _spin,
          ),
        ),
      ],
    );
  }
}

/// One reel card: poster with a bottom scrim (~50% black) keeping the title
/// readable over the art.
class _ReelCard extends StatelessWidget {
  final MediaTitle title;
  final double width;
  final double height;
  final bool landed;
  const _ReelCard({
    required this.title,
    required this.width,
    required this.height,
    required this.landed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: AppMotion.check,
      curve: AppMotion.pop,
      scale: landed ? 1.06 : 1.0,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The name is overlaid below, so no placeholder label.
              Poster(
                imageAsset: title.poster,
                radius: 0,
                fit: BoxFit.cover,
              ),
              // Bottom scrim for label readability.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.5, 1],
                    colors: [Colors.transparent, Color(0xB3000000)],
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Text(
                  title.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.microCaps.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Coin mode (exactly 2 shows)
// ---------------------------------------------------------------------------

class _CoinDecider extends StatefulWidget {
  final List<MediaTitle> titles;
  final ValueChanged<MediaTitle> onDone;
  const _CoinDecider({super.key, required this.titles, required this.onDone});

  @override
  State<_CoinDecider> createState() => _CoinDeciderState();
}

class _CoinDeciderState extends State<_CoinDecider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _chosen = 0;
  bool _flipping = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600));
  }

  void _flip() {
    if (_flipping) return;
    _chosen = math.Random().nextInt(2);
    setState(() => _flipping = true);
    HapticFeedback.selectionClick();
    _ctrl.forward(from: 0).whenComplete(() async {
      HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) widget.onDone(widget.titles[_chosen]);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const diameter = 220.0;
    // 8 half-turns lands back on face A; one extra shows face B.
    final halfTurns = 8 + _chosen;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: diameter + 60,
          child: Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final t = Curves.easeOutQuart.transform(_ctrl.value);
                final angle = math.pi * halfTurns * t;
                final hop = -math.sin(math.min(t, 0.999) * math.pi) * 70;
                final showFront = math.cos(angle) >= 0;
                final face = showFront
                    ? _CoinFace(title: widget.titles[0])
                    : Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationX(math.pi),
                        child: _CoinFace(title: widget.titles[1]),
                      );
                return Transform.translate(
                  offset: Offset(0, hop),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateX(angle),
                    child: SizedBox(
                        width: diameter, height: diameter, child: face),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '${widget.titles[0].name}  vs  ${widget.titles[1].name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: 220,
          child: BrandButton(
            label: _flipping ? 'FLIPPING…' : 'FLIP',
            onTap: _flipping ? null : _flip,
          ),
        ),
      ],
    );
  }
}

/// One coin face: the show's poster in a glowing red ring, with a bottom
/// scrim naming the show.
class _CoinFace extends StatelessWidget {
  final MediaTitle title;
  const _CoinFace({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent, width: 5),
        boxShadow: [
          BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 24),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Poster(imageAsset: title.poster, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.55, 1],
                  colors: [Colors.transparent, Color(0xB3000000)],
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.xl,
              child: Text(
                title.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.microCaps.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

/// Circular counterpart of GlassSurface for the wheel rim and hub.
class _GlassCircle extends StatelessWidget {
  final double diameter;
  final Widget? child;
  const _GlassCircle({required this.diameter, this.child});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: AppGlass.blurSigma, sigmaY: AppGlass.blurSigma),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppGlass.strokeDark, width: 1),
            // BoxDecoration ignores `color` when a gradient is set, so the
            // smoked-glass base tint is baked into the gradient stops.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x4D3A3A3A), Color(0x33202020)],
            ),
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  final WatchlistEntry entry;
  final String again;
  final VoidCallback onWatch;
  final VoidCallback onAgain;
  const _ResultOverlay({
    super.key,
    required this.entry,
    required this.again,
    required this.onWatch,
    required this.onAgain,
  });

  @override
  Widget build(BuildContext context) {
    final title = entry.title;
    final ep = entry.upNext;
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => ColoredBox(
          color: AppColors.overlayScrim.withValues(
              alpha: AppColors.overlayScrim.a * t),
          child: Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: GlassSurface(
              shadow: true,
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("TONIGHT YOU'RE WATCHING",
                      style: AppTextStyles.captionCaps),
                  const SizedBox(height: AppSpacing.lg),
                  // Poster pops in a beat after the card.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.8, end: 1),
                    duration: const Duration(milliseconds: 600),
                    curve: AppMotion.pop,
                    builder: (context, s, child) =>
                        Transform.scale(scale: s, child: child),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.45),
                            blurRadius: 32,
                          ),
                        ],
                      ),
                      child: Poster(
                        width: 160,
                        height: 235,
                        radius: AppRadius.lg,
                        imageAsset: title.poster,
                        label: title.name,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(title.name,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.sectionHeader),
                  if (ep != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'S${ep.season.toString().padLeft(2, '0')} | '
                      'E${ep.number.toString().padLeft(2, '0')}'
                      '${ep.title.isEmpty ? '' : '  ·  ${ep.title}'}',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.subtitle,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: 240,
                    child:
                        BrandButton(label: 'START WATCHING', onTap: onWatch),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: onAgain,
                    child: Text(again,
                        style: AppTextStyles.captionCaps
                            .copyWith(color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
