import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Image;
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
  MediaTitle? _result;
  int _round = 0;

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
            final titles = snap.data!.map((e) => e.title).toList();
            return Stack(
              children: [
                Column(
                  children: [
                    _Header(onClose: () => context.pop()),
                    Expanded(child: _mode(titles)),
                  ],
                ),
                if (_result != null)
                  _ResultOverlay(
                    title: _result!,
                    again: titles.length == 2
                        ? 'FLIP AGAIN'
                        : titles.length <= 8
                            ? 'SPIN AGAIN'
                            : 'ROLL AGAIN',
                    onWatch: () {
                      final t = _result!;
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

  Widget _mode(List<MediaTitle> titles) {
    void done(MediaTitle t) => setState(() => _result = t);
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
Future<ui.Image?> _loadUiImage(String? url) {
  if (url == null || !url.startsWith('http')) return Future.value(null);
  final completer = Completer<ui.Image?>();
  final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _rotation;
  late final List<ui.Image?> _posters;
  int? _chosen;
  bool _spinning = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4600));
    _rotation = const AlwaysStoppedAnimation(0);
    _posters = List.filled(widget.titles.length, null);
    for (var i = 0; i < widget.titles.length; i++) {
      _loadUiImage(widget.titles[i].poster).then((img) {
        if (img == null) return;
        if (!mounted) {
          img.dispose();
          return;
        }
        setState(() => _posters[i] = img);
      });
    }
  }

  void _spin() {
    if (_spinning) return;
    final n = widget.titles.length;
    final sweep = 2 * math.pi / n;
    final i = math.Random().nextInt(n);
    // Land segment i's center under the top pointer after 5 full turns.
    final target = 5 * 2 * math.pi - (i * sweep + sweep / 2);
    _rotation = Tween<double>(begin: 0, end: target).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart));
    setState(() {
      _chosen = i;
      _spinning = true;
    });
    HapticFeedback.selectionClick();
    _ctrl.forward(from: 0).whenComplete(() async {
      HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) widget.onDone(widget.titles[i]);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
            math.min(box.maxWidth - AppSpacing.xxl * 2, box.maxHeight - 140),
            380.0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: size + 24,
              height: size + 24,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _GlassCircle(diameter: size + 24),
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) => Transform.rotate(
                      angle: _rotation.value,
                      child: CustomPaint(
                        size: Size.square(size - 8),
                        painter: _WheelPainter(
                          labels: widget.titles.map((t) => t.name).toList(),
                          posters: _posters,
                          highlight: _spinning && _ctrl.isCompleted
                              ? _chosen
                              : null,
                        ),
                      ),
                    ),
                  ),
                  _GlassCircle(
                    diameter: size * 0.20,
                    child: const Icon(Icons.casino,
                        color: AppColors.accentAlt, size: 26),
                  ),
                  Positioned(
                    top: -6,
                    child: CustomPaint(
                      size: const Size(26, 30),
                      painter: _PointerPainter(),
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
                onTap: _spinning ? null : _spin,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Poster-art segments under a ~50% black scrim so the wrapped 2-line
/// labels stay readable; falls back to alternating red/smoked fills while
/// artwork loads.
class _WheelPainter extends CustomPainter {
  final List<String> labels;
  final List<ui.Image?> posters;
  final int? highlight;
  _WheelPainter({
    required this.labels,
    required this.posters,
    this.highlight,
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
      canvas.save();
      canvas.clipPath(sector);
      if (img != null) {
        // Cover-fit the poster into the sector's bounding box.
        final bbox = sector.getBounds();
        final scale = math.max(
            bbox.width / img.width, bbox.height / img.height);
        final dst = Rect.fromCenter(
          center: bbox.center,
          width: img.width * scale,
          height: img.height * scale,
        );
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          dst,
          Paint()..filterQuality = FilterQuality.medium,
        );
        // Readability scrim over the artwork.
        canvas.drawRect(bbox, Paint()..color = const Color(0x80000000));
      } else {
        final fill = i.isEven
            ? _reds[(i ~/ 2).isEven ? 0 : 1]
            : AppColors.surfaceElevated;
        canvas.drawPath(sector, Paint()..color = fill);
      }
      canvas.restore();
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x40FFFFFF),
      );
    }

    if (highlight != null) {
      final start = -math.pi / 2 + highlight! * sweep;
      canvas.drawArc(
        rect.deflate(1),
        start,
        sweep,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.white
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // Radial labels, wrapped to two lines like Excel cell wrap.
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * sweep + sweep / 2;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: AppTextStyles.microCaps.copyWith(
            color: Colors.white,
            fontSize: n > 6 ? 10 : 11,
            letterSpacing: 0.2,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
        maxLines: 2,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: radius * 0.52);
      tp.paint(canvas, Offset(radius * 0.32, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.labels != labels ||
      old.highlight != highlight ||
      old.posters != posters;
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, AppColors.love, 6, false);
    canvas.drawPath(path, Paint()..color = AppColors.love);
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
    _scroll = ScrollController(initialScrollOffset: _n * 2 * _extent);
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
      duration: const Duration(milliseconds: 4200),
      curve: Curves.easeOutQuart,
    );
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
              Poster(
                imageAsset: title.poster,
                label: title.name,
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
            Poster(
              imageAsset: title.poster,
              label: title.name,
              fit: BoxFit.cover,
            ),
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
  final MediaTitle title;
  final String again;
  final VoidCallback onWatch;
  final VoidCallback onAgain;
  const _ResultOverlay({
    required this.title,
    required this.again,
    required this.onWatch,
    required this.onAgain,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.overlayScrim,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: GlassSurface(
              shadow: true,
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('TONIGHT YOU\'RE WATCHING',
                      style: AppTextStyles.captionCaps),
                  const SizedBox(height: AppSpacing.lg),
                  Poster(
                    width: 160,
                    height: 235,
                    radius: AppRadius.lg,
                    imageAsset: title.poster,
                    label: title.name,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(title.name,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.sectionHeader),
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
