import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show AssetBundle;

import 'labels/label_composer.dart';
import 'labels/tape_label_data.dart';
import 'plates/image_lru.dart';
import 'plates/plate_cache.dart';
import 'plates/plate_compositor.dart';
import 'plates/plate_manifest.dart';
import 'rail_card.dart';
import 'shelf_layout.dart';
import 'tape_source.dart';

/// Paints the label atlas for one tape at [widthPx] (shelf `spine` atlas).
typedef SpineArtPainter = Future<ui.Image> Function(
    TapeLabelData data, int widthPx);

/// Paints the square hero atlas (all five regions) at [sizePx].
typedef HeroArtPainter = Future<ui.Image> Function(
    TapeLabelData data, int sizePx);

/// One composed bay: everything but the rail, plus the rail on its own so
/// it can move with a little parallax.
class ShelfRowImage {
  ShelfRowImage(this.base, this.rail, this.railRect);

  /// Bay, shadows and tapes, at the composed width.
  final ui.Image base;

  /// The rail and its section card.
  final ui.Image rail;

  /// Where [rail] sits, in bay pixels.
  final Rect railRect;

  int get bytes => ImageLru.bytesOf(base) + ImageLru.bytesOf(rail);

  ShelfRowImage clone() => ShelfRowImage(base.clone(), rail.clone(), railRect);

  void dispose() {
    base.dispose();
    rail.dispose();
  }
}

/// Composes shelf bays offscreen and caches them, so scrolling only blits.
///
/// Rows are composed asynchronously on request (one or two at a time, the
/// most recently requested first, so a fling composes what is on screen
/// now rather than what it flew past) and kept in a byte-budgeted LRU. Spine
/// art is composed by [LabelComposer] at `144 px × on-screen scale` and kept
/// in its own LRU, as are the rail cards. Budgets are listed on
/// [PlateImageCache].
class ShelfRenderer extends ChangeNotifier {
  ShelfRenderer({
    required this.source,
    AssetBundle? bundle,
    SpineArtPainter? spinePainter,
    HeroArtPainter? heroPainter,
    this.labelPatience = const Duration(milliseconds: 2500),
  })  : _bundle = bundle,
        plates = PlateImageCache(
            bundle: bundle, budgetBytes: PlateImageCache.shelfBudgetBytes),
        _spinePainter = spinePainter ??
            ((d, w) => LabelComposer().composeShelf(d, widthPx: w)),
        heroPainter = heroPainter ??
            ((d, s) => LabelComposer().composeHero(d, sizePx: s)) {
    source.addListener(_onSource);
    _init = _load();
  }

  final TapeSource source;
  final AssetBundle? _bundle;
  final SpineArtPainter _spinePainter;

  /// Paints the inspect view's hero atlas.
  final HeroArtPainter heroPainter;
  final PlateImageCache plates;

  /// How long a row waits for titles and artwork before composing without
  /// them (they are recomposed in when they arrive).
  final Duration labelPatience;

  static const int rowBudgetBytes = 28 << 20;
  static const int artBudgetBytes = 12 << 20;
  static const int tagBudgetBytes = 3 << 20;

  /// Row images are composed at the device-pixel width, within these
  /// bounds (fractions of the 1116 px plates).
  static const double minRowScale = 0.5;
  static const double maxRowScale = 1.5;

  final Map<String, ShelfRowImage> _rows = {};
  int _rowBytes = 0;
  final Map<String, String> _latest = {};
  final ImageLru<String> _art = ImageLru(budgetBytes: artBudgetBytes);
  final ImageLru<String> _tags = ImageLru(budgetBytes: tagBudgetBytes);
  final Map<String, Future<bool>> _artJobs = {};
  final Map<String, Future<void>> _tagJobs = {};

  late final Future<void> _init;
  PlateManifest? _manifest;
  ShelfLayout? _layout;
  PlateCompositor? _compositor;
  Object? _initError;

  /// Who is lifted out of the shelf for inspection (hidden on the shelf).
  final ValueNotifier<String?> inspecting = ValueNotifier(null);

  /// Flips to true once the manifest and compositor are loaded.
  final ValueNotifier<bool> loaded = ValueNotifier(false);

  bool _disposed = false;
  int _users = 0;

  bool get isDisposed => _disposed;

  Future<void> get ready => _init;
  PlateManifest? get manifest => _manifest;
  ShelfLayout? get layout => _layout;
  PlateCompositor? get compositor => _compositor;
  Object? get initError => _initError;
  AssetBundle? get bundle => _bundle;

  Future<void> _load() async {
    try {
      final m = await PlateManifest.load(_bundle);
      _compositor = await PlateCompositor.create();
      _manifest = m;
      _layout = ShelfLayout.of(m);
    } catch (e) {
      _initError = e;
      debugPrint('Shelf plates unavailable: $e');
    }
    if (!_disposed) {
      loaded.value = _layout != null;
      notifyListeners();
    }
  }

  void _onSource() {
    if (!_disposed) notifyListeners();
  }

  /// Shelf widgets register while mounted; when the last one goes, the
  /// composed rows and art are released (the plates stay, see budgets).
  void attach() => _users++;

  void detach() {
    _users--;
    if (_users <= 0) {
      _users = 0;
      trim();
    }
  }

  /// Drops every composed row, spine and card.
  void trim() {
    _queue.clear();
    for (final r in _rows.values) {
      r.dispose();
    }
    _rows.clear();
    _rowBytes = 0;
    _latest.clear();
    _art.clear();
    _tags.clear();
  }

  // -------------------------------------------------------------------
  // Keys
  // -------------------------------------------------------------------

  /// The composed width for a bay shown [logicalWidth] wide at [dpr].
  int rowWidthPx(double logicalWidth, double dpr) {
    final bay = _manifest?.shelf.bayPx.width ?? 1116;
    return (logicalWidth * dpr)
        .clamp(bay * minRowScale, bay * maxRowScale)
        .round();
  }

  /// Spine art width for a row composed [rowWidthPx] wide.
  int artWidthFor(int rowWidthPx) {
    final bay = _manifest?.shelf.bayPx.width ?? 1116;
    final atlas = _manifest?.atlases['spine'];
    final base = (atlas?.canvasMm.width ?? 48) *
        (_manifest?.shelf.pxPerMm ?? 3); // 144 px at 1 : 1
    return (base * rowWidthPx / bay).round().clamp(48, 256);
  }

  String _slotKey(ShelfBay bay, int widthPx) => '${bay.key}@$widthPx';

  /// Identity of the pixels [bay] would compose to right now.
  String rowKey(ShelfBay bay, int widthPx) {
    final b = StringBuffer(_slotKey(bay, widthPx));
    for (final t in bay.tapes) {
      b
        ..write('|')
        ..write(source.labelKey(t.titleId));
    }
    return b.toString();
  }

  /// The row for [bay] if composed with today's labels; else the last one
  /// composed for the same tapes (stale but close), else null. Draw it
  /// right away; clone to keep.
  ShelfRowImage? rowFor(ShelfBay bay, int widthPx, {bool allowStale = true}) {
    final exact = _rows[rowKey(bay, widthPx)];
    if (exact != null) return _touch(rowKey(bay, widthPx), exact);
    if (!allowStale) return null;
    final last = _latest[_slotKey(bay, widthPx)];
    final stale = last == null ? null : _rows[last];
    return stale == null ? null : _touch(last!, stale);
  }

  bool isCurrent(ShelfBay bay, int widthPx) =>
      _rows.containsKey(rowKey(bay, widthPx));

  ShelfRowImage _touch(String key, ShelfRowImage r) {
    _rows.remove(key);
    _rows[key] = r;
    return r;
  }

  void _putRow(String key, String slot, ShelfRowImage r) {
    final old = _rows.remove(key);
    if (old != null) {
      _rowBytes -= old.bytes;
      old.dispose();
    }
    _rows[key] = r;
    _rowBytes += r.bytes;
    _latest[slot] = key;
    while (_rows.length > 1 && _rowBytes > rowBudgetBytes) {
      final k = _rows.keys.first;
      final v = _rows.remove(k)!;
      _rowBytes -= v.bytes;
      v.dispose();
    }
  }

  @visibleForTesting
  int get rowBytes => _rowBytes;
  @visibleForTesting
  int get rowCount => _rows.length;
  @visibleForTesting
  int get artBytes => _art.bytes;

  // -------------------------------------------------------------------
  // Work queue
  // -------------------------------------------------------------------

  final LinkedHashMap<String, _RowJob> _queue = LinkedHashMap();
  final Set<String> _running = {};
  final List<Completer<void>> _idleWaiters = [];
  static const int _parallel = 2;

  bool get isIdle => _queue.isEmpty && _running.isEmpty;

  /// Completes when nothing is queued or composing.
  Future<void> whenIdle() {
    if (isIdle) return Future.value();
    final c = Completer<void>();
    _idleWaiters.add(c);
    return c.future;
  }

  /// Queues [bay] for composition unless it is current or already queued.
  /// Later requests run first.
  void request(ShelfBay bay, int widthPx) {
    if (_layout == null) return;
    final key = rowKey(bay, widthPx);
    if (_rows.containsKey(key) || _running.contains(key)) return;
    _queue.remove(key);
    _queue[key] = _RowJob(bay, widthPx);
    _pump();
  }

  /// Forgets a queued (not yet started) request.
  void cancel(ShelfBay bay, int widthPx) => _queue.remove(rowKey(bay, widthPx));

  void _pump() {
    while (_running.length < _parallel && _queue.isNotEmpty) {
      final key = _queue.keys.last;
      final job = _queue.remove(key)!;
      _running.add(key);
      composeRow(job.bay, job.widthPx).then((_) {}, onError: (Object e) {
        debugPrint('Shelf row failed: $e');
      }).whenComplete(() {
        _running.remove(key);
        if (!_disposed) {
          notifyListeners();
          _pump();
        }
        if (isIdle) {
          for (final c in _idleWaiters) {
            c.complete();
          }
          _idleWaiters.clear();
        }
      });
    }
  }

  // -------------------------------------------------------------------
  // Composition
  // -------------------------------------------------------------------

  /// Composes [bay] at [widthPx] now (waiting for labels up to
  /// [labelPatience]) and caches it under the key it was requested with.
  Future<ShelfRowImage> composeRow(ShelfBay bay, int widthPx) async {
    await _init;
    final m = _manifest, layout = _layout, comp = _compositor;
    if (m == null || layout == null || comp == null) {
      throw StateError('shelf plates unavailable: $_initError');
    }
    final key = rowKey(bay, widthPx);
    final g = m.shelf;
    final scale = widthPx / g.bayPx.width;
    final heightPx = (g.bayPx.height * scale).round();
    final artW = artWidthFor(widthPx);

    final names = {for (final d in bay.draws) d.plate};
    final imgs = <String, PlateImages>{};
    final arts = <int, ui.Image?>{};
    ui.Image? tag;
    try {
      await Future.wait([
        for (final n in names)
          plates.acquirePlate(m.shelfPlate(n)).then((i) => imgs[n] = i),
        for (var i = 0; i < bay.tapes.length; i++)
          spineArt(bay.tapes[i].titleId, artW).then((a) => arts[i] = a),
        tagArt(bay.tag, scale).then((t) => tag = t),
      ]);
      if (_disposed) throw StateError('disposed');

      Rect px(Rect r) => Rect.fromLTRB(
          r.left * scale, r.top * scale, r.right * scale, r.bottom * scale);
      final inner = px(g.innerRect);
      final draws = <PlateDraw>[];
      ShelfDraw? railDraw;
      for (final d in bay.draws) {
        if (d.tag) {
          railDraw = d;
          continue;
        }
        draws.add(PlateDraw(
          images: imgs[d.plate]!,
          dst: px(d.rect),
          art: d.tape == null ? null : arts[d.tape!],
          clip: d.clipInner ? inner : null,
        ));
      }
      final base = await comp.render(widthPx, heightPx, draws);
      final railRect = railDraw!.rect;
      final rw = (railRect.width * scale).round();
      final rh = (railRect.height * scale).round();
      final rail = await comp.render(rw, math.max(1, rh), [
        PlateDraw(
          images: imgs['rail']!,
          dst: Rect.fromLTWH(0, 0, rw.toDouble(), rh.toDouble()),
          art: tag,
        ),
      ]);
      final row = ShelfRowImage(base, rail, railRect);
      if (_disposed) {
        row.dispose();
        throw StateError('disposed');
      }
      _putRow(key, _slotKey(bay, widthPx), row);
      return row;
    } finally {
      for (final i in imgs.values) {
        i.dispose();
      }
      for (final a in arts.values) {
        a?.dispose();
      }
      tag?.dispose();
    }
  }

  /// The spine atlas of [titleId] at [widthPx], as a caller-owned image
  /// (null while nothing is known about the title).
  Future<ui.Image?> spineArt(String titleId, int widthPx) async {
    final key = '$titleId|${source.labelKey(titleId)}|$widthPx';
    for (var attempt = 0; attempt < 3; attempt++) {
      final hit = _art.get(key);
      if (hit != null) return hit.clone();
      final made = await (_artJobs[key] ??=
          _composeArt(titleId, widthPx, key).whenComplete(() {
        _artJobs.remove(key);
      }));
      if (!made) return null;
      // Evicted again before we got here (heavy churn): compose once more.
    }
    return null;
  }

  /// Composes into the art cache; false when the title is unknown.
  Future<bool> _composeArt(String titleId, int widthPx, String key) async {
    final snap = await source.labelData(titleId, patience: labelPatience);
    if (snap == null) return false;
    try {
      final img = await _spinePainter(snap.data, widthPx);
      if (_disposed) {
        img.dispose();
        return false;
      }
      _art.put(key, img);
      return true;
    } finally {
      snap.dispose();
    }
  }

  /// The rail card for [text] at row [scale], caller-owned.
  Future<ui.Image> tagArt(String text, double scale) async {
    final pxPerMm = ((_manifest?.shelf.pxPerMm ?? 3) * scale * 4).round() / 4;
    final key = '$text@$pxPerMm';
    final atlas = _manifest!.atlases['tag']!;
    for (var attempt = 0; attempt < 3; attempt++) {
      final hit = _tags.get(key);
      if (hit != null) return hit.clone();
      await (_tagJobs[key] ??= RailCard.render(text, atlas, pxPerMm: pxPerMm)
          .then((i) => _tags.put(key, i))
          .whenComplete(() {
        _tagJobs.remove(key);
      }));
    }
    return RailCard.render(text, atlas, pxPerMm: pxPerMm);
  }

  /// [bay]'s tape [index] on its own (its plate and spine art, transparent
  /// elsewhere), at the row scale for [rowWidthPx]: the sprite that lifts
  /// out of the shelf. Returns the image and its rect in bay pixels.
  Future<(ui.Image, Rect)?> tapeSprite(
      ShelfBay bay, int index, int rowWidthPx) async {
    await _init;
    final m = _manifest, comp = _compositor;
    final d = bay.drawForTape(index);
    if (m == null || comp == null || d == null) return null;
    final scale = rowWidthPx / m.shelf.bayPx.width;
    final images = await plates.acquirePlate(m.shelfPlate(d.plate));
    final art = await spineArt(bay.tapes[index].titleId, artWidthFor(rowWidthPx));
    try {
      final w = (d.rect.width * scale).round(), h = (d.rect.height * scale).round();
      final img = await comp.render(w, h, [
        PlateDraw(
            images: images,
            art: art,
            dst: Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())),
      ]);
      return (img, d.rect);
    } finally {
      images.dispose();
      art?.dispose();
    }
  }

  final Map<String, Future<Rect>> _bounds = {};

  /// The opaque part of a shelf plate (alpha ≥ 50 %), in plate pixels.
  Future<Rect> opaqueBounds(String plate) {
    return _bounds[plate] ??= () async {
      final m = _manifest!;
      final img = await plates.acquire(m.shelfPlate(plate).color);
      try {
        final b = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        return alphaBounds(b.buffer.asUint8List(), img.width, img.height);
      } finally {
        img.dispose();
      }
    }();
  }

  @visibleForTesting
  static Rect alphaBounds(Uint8List rgba, int w, int h) {
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (rgba[(y * w + x) * 4 + 3] >= 128) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) return Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    return Rect.fromLTRB(
        x0.toDouble(), y0.toDouble(), x1 + 1.0, y1 + 1.0);
  }

  @override
  void dispose() {
    _disposed = true;
    source.removeListener(_onSource);
    trim();
    plates.clear();
    inspecting.dispose();
    loaded.dispose();
    for (final c in _idleWaiters) {
      c.complete();
    }
    super.dispose();
  }
}

class _RowJob {
  _RowJob(this.bay, this.widthPx);
  final ShelfBay bay;
  final int widthPx;
}
