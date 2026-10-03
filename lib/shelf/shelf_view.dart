import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../state/app_state.dart';
import 'inspect/tape_inspector.dart';
import 'shelf_layout.dart';
import 'shelf_renderer.dart';
import 'tape_catalog.dart';

/// Provides a [ShelfRenderer] to the shelf widgets below it. Without one,
/// [ShelfScope.of] uses an app-wide renderer built over the
/// [ContentRepository] and [AppState] providers.
class ShelfScope extends InheritedWidget {
  const ShelfScope({super.key, required this.renderer, required super.child});

  final ShelfRenderer renderer;

  static final Expando<ShelfRenderer> _shared = Expando();

  static ShelfRenderer of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShelfScope>();
    if (scope != null) return scope.renderer;
    final appState = context.read<AppState>();
    return _shared[appState] ??= ShelfRenderer(
      source: TapeCatalog(
          repo: context.read<ContentRepository>(), appState: appState),
    );
  }

  @override
  bool updateShouldNotify(ShelfScope old) => old.renderer != renderer;
}

/// Called when a tape is tapped: [plateRect] is where its plate image
/// sits on screen (global coordinates).
typedef TapeTapCallback = void Function(
    ShelfBay bay, int tape, Rect plateRect, int rowWidthPx);

/// Narrowest bay before a wider shelf puts bays side by side.
const double _targetBayWidth = 400;

int _columnsFor(double width) =>
    math.max(1, (width / _targetBayWidth).floor());

List<ShelfBay> _bays(ShelfRenderer r, List<ShelfSection> sections) {
  final layout = r.layout;
  if (layout == null) return const [];
  final hidden = r.inspecting.value;
  return layout.layout(sections, hidden: hidden == null ? const {} : {hidden});
}

/// A non-scrolling shelf (a few bays), e.g. the profile's favourites.
class ShelfColumn extends StatelessWidget {
  const ShelfColumn({super.key, required this.sections, this.onTapTape});

  final List<ShelfSection> sections;
  final TapeTapCallback? onTapTape;

  @override
  Widget build(BuildContext context) {
    final r = ShelfScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([r.loaded, r.inspecting]),
      builder: (context, _) {
        final bays = _bays(r, sections);
        return LayoutBuilder(builder: (context, box) {
          final cols = _columnsFor(box.maxWidth);
          final bayW = box.maxWidth / cols;
          final bands = (bays.length + cols - 1) ~/ cols;
          if (r.layout == null) {
            return SizedBox(
                height: bayW * 690 / 1116,
                child: const _ShelfLoading());
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var b = 0; b < bands; b++)
                _Band(
                  bays: bays,
                  first: b * cols,
                  cols: cols,
                  bayWidth: bayW,
                  onTapTape: onTapTape,
                ),
            ],
          );
        });
      },
    );
  }
}

/// A lazily built shelf for long collections: only bands near the
/// viewport exist, and only they compose.
class SliverShelf extends StatelessWidget {
  const SliverShelf({super.key, required this.sections, this.onTapTape});

  final List<ShelfSection> sections;
  final TapeTapCallback? onTapTape;

  @override
  Widget build(BuildContext context) {
    final r = ShelfScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([r.loaded, r.inspecting]),
      builder: (context, _) {
        final bays = _bays(r, sections);
        return SliverLayoutBuilder(builder: (context, c) {
          final width = c.crossAxisExtent;
          final cols = _columnsFor(width);
          final bayW = width / cols;
          final bandH = bayW * 690 / 1116;
          if (r.layout == null) {
            return SliverToBoxAdapter(
                child: SizedBox(height: bandH, child: const _ShelfLoading()));
          }
          final bands = (bays.length + cols - 1) ~/ cols;
          return SliverFixedExtentList(
            itemExtent: bandH,
            delegate: SliverChildBuilderDelegate(
              (context, b) => _Band(
                bays: bays,
                first: b * cols,
                cols: cols,
                bayWidth: bayW,
                onTapTape: onTapTape,
              ),
              childCount: bands,
            ),
          );
        });
      },
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({
    required this.bays,
    required this.first,
    required this.cols,
    required this.bayWidth,
    this.onTapTape,
  });

  final List<ShelfBay> bays;
  final int first;
  final int cols;
  final double bayWidth;
  final TapeTapCallback? onTapTape;

  @override
  Widget build(BuildContext context) {
    final r = ShelfScope.of(context);
    final h = bayWidth * 690 / 1116;
    return SizedBox(
      height: h,
      child: Row(
        children: [
          for (var i = first; i < first + cols; i++)
            SizedBox(
              width: bayWidth,
              height: h,
              child: i < bays.length
                  ? ShelfBayView(
                      key: ValueKey('bay-${bays[i].index}'),
                      bay: bays[i],
                      onTapTape: onTapTape,
                    )
                  : ShelfBayView(
                      key: ValueKey('bay-$i'),
                      bay: r.layout!.layoutBay(i, const [], ''),
                    ),
            ),
        ],
      ),
    );
  }
}

/// One bay: its composed image (or a shimmer while composing), the rail
/// with a little parallax, and one tap target per tape.
class ShelfBayView extends StatefulWidget {
  const ShelfBayView({super.key, required this.bay, this.onTapTape});

  final ShelfBay bay;
  final TapeTapCallback? onTapTape;

  @override
  State<ShelfBayView> createState() => _ShelfBayViewState();
}

class _ShelfBayViewState extends State<ShelfBayView>
    with SingleTickerProviderStateMixin {
  ShelfRenderer? _r;
  ShelfRowImage? _row; // our clone
  int _widthPx = 0;
  late final AnimationController _shimmer = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  ScrollPosition? _scroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = ShelfScope.of(context);
    if (!identical(r, _r)) {
      _r?.removeListener(_onRenderer);
      _r?.detach();
      _r = r..addListener(_onRenderer);
      r.attach();
    }
    _scroll = Scrollable.maybeOf(context)?.position;
  }

  void _onRenderer() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ShelfBayView old) {
    super.didUpdateWidget(old);
    if (old.bay.key != widget.bay.key) _r?.cancel(old.bay, _widthPx);
  }

  @override
  void dispose() {
    _r?.cancel(widget.bay, _widthPx);
    _r?.removeListener(_onRenderer);
    _r?.detach();
    _row?.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  void _adopt(ShelfRowImage? fresh) {
    if (fresh == null) return;
    if (_row != null && identical(_row!.base, fresh.base)) return;
    if (_row != null &&
        _row!.base.isCloneOf(fresh.base) &&
        _row!.rail.isCloneOf(fresh.rail)) {
      return;
    }
    _row?.dispose();
    _row = fresh.clone();
  }

  double _parallax() {
    final box = context.findRenderObject() as RenderBox?;
    final vp = Scrollable.maybeOf(context)?.context.findRenderObject()
        as RenderBox?;
    if (box == null || vp == null || !box.attached || !vp.attached) return 0;
    final y = box
        .localToGlobal(Offset(0, box.size.height / 2), ancestor: vp)
        .dy;
    final h = vp.size.height;
    if (h <= 0) return 0;
    return ((y - h / 2) / h).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final r = _r!;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(builder: (context, box) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      _widthPx = r.rowWidthPx(box.maxWidth, dpr);
      final bay = widget.bay;
      _adopt(r.rowFor(bay, _widthPx));
      final current = r.isCurrent(bay, _widthPx);
      if (!current) r.request(bay, _widthPx);
      final loading = _row == null;
      if (loading && !reduce) {
        if (!_shimmer.isAnimating) _shimmer.repeat();
      } else if (_shimmer.isAnimating) {
        _shimmer.stop();
      }
      final m = r.manifest!;
      final scale = box.maxWidth / m.shelf.bayPx.width;
      final placeholder = r.plates.peek(m.shelfPlate(bay.draws.first.plate).color);
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _BayPainter(
                  row: _row,
                  placeholder: placeholder,
                  shimmer: loading && !reduce ? _shimmer : null,
                  parallax: reduce ? null : _parallax,
                  scroll: reduce ? null : _scroll,
                  bayWidth: m.shelf.bayPx.width,
                ),
              ),
            ),
          ),
          if (bay.tag.isNotEmpty)
            Positioned.fromRect(
              rect: _scaled(r.manifest!.shelfPlate('rail').crop, scale),
              child: Semantics(
                  container: true,
                  header: true,
                  label: bay.tag,
                  child: const SizedBox.expand()),
            ),
          for (var i = 0; i < bay.tapes.length; i++)
            if (bay.drawForTape(i) != null)
              Positioned.fromRect(
                rect: _scaled(bay.tapeRects[i], scale),
                child: _TapeTarget(
                  label: r.source.semanticsLabel(bay.tapes[i].titleId),
                  onTap: () => _tap(i, scale),
                ),
              ),
        ],
      );
    });
  }

  static Rect _scaled(Rect r, double s) =>
      Rect.fromLTRB(r.left * s, r.top * s, r.right * s, r.bottom * s);

  void _tap(int i, double scale) {
    HapticFeedback.selectionClick();
    final box = context.findRenderObject() as RenderBox?;
    final draw = widget.bay.drawForTape(i);
    if (box == null || draw == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final plate = _scaled(draw.rect, scale).shift(origin);
    final cb = widget.onTapTape;
    if (cb != null) {
      cb(widget.bay, i, plate, _widthPx);
    } else {
      TapeInspector.show(context,
          renderer: _r!,
          bay: widget.bay,
          tape: i,
          plateRect: plate,
          rowWidthPx: _widthPx);
    }
  }
}

class _TapeTarget extends StatelessWidget {
  const _TapeTarget({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      hint: 'Double tap to inspect',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
      ),
    );
  }
}

class _BayPainter extends CustomPainter {
  _BayPainter({
    required this.row,
    required this.placeholder,
    required this.shimmer,
    required this.parallax,
    required this.scroll,
    required this.bayWidth,
  }) : super(repaint: Listenable.merge([shimmer, scroll]));

  final ShelfRowImage? row;
  final ui.Image? placeholder;
  final Animation<double>? shimmer;
  final double Function()? parallax;
  final ScrollPosition? scroll;
  final double bayWidth;

  /// Largest rail shift, logical px.
  static const double _parallaxPx = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.clipRect(dst);
    final r = row;
    if (r == null) {
      _placeholder(canvas, size);
      return;
    }
    final down = size.width < r.base.width;
    final paint = Paint()
      ..filterQuality = down ? FilterQuality.medium : FilterQuality.low;
    canvas.drawImageRect(
        r.base,
        Rect.fromLTWH(0, 0, r.base.width.toDouble(), r.base.height.toDouble()),
        dst,
        paint);
    final s = size.width / bayWidth;
    final dy = parallax == null ? 0.0 : parallax!() * _parallaxPx;
    final railDst = Rect.fromLTWH(r.railRect.left * s,
        r.railRect.top * s + dy, r.railRect.width * s, r.railRect.height * s);
    canvas.drawImageRect(
        r.rail,
        Rect.fromLTWH(0, 0, r.rail.width.toDouble(), r.rail.height.toDouble()),
        railDst,
        paint);
  }

  void _placeholder(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final p = placeholder;
    if (p != null) {
      canvas.drawImageRect(
          p,
          Rect.fromLTWH(0, 0, p.width.toDouble(), p.height.toDouble()),
          dst,
          Paint()..filterQuality = FilterQuality.medium);
    } else {
      canvas.drawRect(
          dst,
          Paint()
            ..shader = ui.Gradient.linear(dst.topCenter, dst.bottomCenter,
                const [Color(0xFF2A1C14), Color(0xFF140D09)]));
    }
    final t = shimmer?.value;
    if (t == null) return;
    final x = -size.width * 0.6 + t * size.width * 2.2;
    canvas.drawRect(
        dst,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset(x, 0),
            Offset(x + size.width * 0.5, size.height * 0.3),
            const [Color(0x00FFFFFF), Color(0x14FFF4E0), Color(0x00FFFFFF)],
            const [0, 0.5, 1],
          ));
  }

  @override
  bool shouldRepaint(_BayPainter old) =>
      old.row != row ||
      old.placeholder != placeholder ||
      old.shimmer != shimmer ||
      (old.parallax == null) != (parallax == null);
}

class _ShelfLoading extends StatelessWidget {
  const _ShelfLoading();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A1C14), Color(0xFF140D09)],
          ),
        ),
      );
}
