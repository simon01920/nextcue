import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show AssetBundle;

import '../plates/image_lru.dart';
import '../plates/plate_cache.dart';
import '../plates/plate_compositor.dart';
import '../plates/plate_manifest.dart';

/// The inspect view's pictures of one tape: rotation frames, the hi-res
/// front and the cassette, each composited once with the title's hero
/// label atlas and then kept as a single image.
///
/// Sources are decoded on demand into a private [PlateImageCache] and
/// evicted as soon as their frame is composited, so the three 6.9 MB source
/// images of a frame never outlive it; composited frames (≤ 2.3 MB each,
/// smaller on small screens) live in a 24 MiB LRU — about ten full-size
/// frames around where the user is looking. `front_hi` (27.6 MB of sources)
/// is composited once at display size and only the result is kept.
class HeroFrames extends ChangeNotifier {
  HeroFrames({
    required this.manifest,
    required this.compositor,
    AssetBundle? bundle,
  }) : _sources = PlateImageCache(
            bundle: bundle, budgetBytes: PlateImageCache.heroBudgetBytes);

  final PlateManifest manifest;
  final PlateCompositor compositor;
  final PlateImageCache _sources;

  static const int frameBudgetBytes = 24 << 20;

  HeroGroup get group => manifest.hero;

  final ImageLru<int> _frames = ImageLru(budgetBytes: frameBudgetBytes);
  ui.Image? _atlas;
  ui.Image? _front;
  ui.Image? _cassette;
  double? _cassetteFor;
  int _epoch = 0;
  bool _disposed = false;

  /// Composited frame height, device px (frames are never upscaled).
  double displayHeightPx = 900;

  /// Cassette display width, device px.
  double cassetteWidthPx = 600;

  bool get hasAtlas => _atlas != null;

  /// Takes ownership of [atlas] (the hero label atlas) and recomposites
  /// everything from it, keeping the old pictures on screen until the new
  /// ones are ready.
  void setAtlas(ui.Image atlas) {
    _atlas?.dispose();
    _atlas = atlas;
    _epoch++;
    _failed.clear();
    _stale
      ..clear()
      ..addAll(_frames.keys);
    _frontStale = _front != null;
    _cassetteStale = _cassette != null;
    notifyListeners();
    _pump();
  }

  final Set<int> _stale = {};
  bool _frontStale = false;
  bool _cassetteStale = false;

  /// The composited frame [index] (an available frame), if ready.
  ui.Image? frame(int index) => _frames.get(index);

  /// The ready frame closest to [index] around the turn, if any.
  ui.Image? nearestReady(int index) {
    final n = group.frames;
    for (var d = 0; d <= n ~/ 2; d++) {
      for (final f in [index + d, index - d]) {
        final img = _frames.get(f % n);
        if (img != null) return img;
      }
    }
    return null;
  }

  bool isReady(int index) => _frames.containsKey(index) && !_stale.contains(index);

  ui.Image? get front => _front;
  ui.Image? get cassette => _cassette;

  // -------------------------------------------------------------------
  // Queue: one composition at a time; the end of [_queue] runs first.
  // -------------------------------------------------------------------

  final List<_Job> _queue = [];
  _Job? _current;

  /// Jobs that failed with the current atlas; not retried until it changes
  /// (a frame that cannot be composited must not be retried every build).
  final Set<_Job> _failed = {};

  /// Whether anything failed to composite with the current atlas.
  bool get hasFailures => _failed.isNotEmpty;

  /// Nothing queued or compositing.
  bool get isIdle => _current == null && _queue.isEmpty;

  void _enqueue(_Job job, {required bool urgent}) {
    if (job == _current || _failed.contains(job)) return;
    _queue.remove(job);
    urgent ? _queue.add(job) : _queue.insert(0, job);
    _pump();
  }

  /// Asks for the available frames nearest [frames], ahead of anything
  /// queued before; the first one is composited first.
  void want(Iterable<int> frames) {
    final list = [for (final f in frames) group.nearestAvailable(f)];
    for (final f in list.reversed) {
      if (!isReady(f)) _enqueue(_Job.frame(f), urgent: true);
    }
  }

  /// The hi-res front; [urgent] when the user is looking at the front now.
  void wantFront({bool urgent = false}) {
    if (_front != null && !_frontStale) return;
    _enqueue(const _Job.front(), urgent: urgent);
  }

  void wantCassette(double progress) {
    final spec = group.cassetteFor(progress);
    if (spec == null) return;
    final p = spec.progress!;
    if (_cassette != null && _cassetteFor == p && !_cassetteStale) return;
    _queue.removeWhere((j) => j.kind == _JobKind.cassette && j.progress != p);
    _enqueue(_Job.cassette(p), urgent: false);
  }

  Future<void> _pump() async {
    if (_current != null || _atlas == null || _disposed) return;
    while (_queue.isNotEmpty && !_disposed) {
      final job = _current = _queue.removeLast();
      final epoch = _epoch;
      final (PlateSpec? spec, double scale) = switch (job.kind) {
        _JobKind.front => (group.frontHi, displayHeightPx / 1800),
        _JobKind.cassette =>
          (group.cassetteFor(job.progress), cassetteWidthPx / 900),
        _JobKind.frame =>
          (group.framePlates[job.frame], displayHeightPx / 900),
      };
      final img = await _composite(spec, scale);
      _current = null;
      if (img == null) {
        if (epoch == _epoch) _failed.add(job);
        notifyListeners();
        continue;
      }
      if (_disposed) {
        img.dispose();
        break;
      }
      if (epoch != _epoch) {
        // Printed with an atlas that has since been replaced: redo it.
        img.dispose();
        _queue.add(job);
        continue;
      }
      switch (job.kind) {
        case _JobKind.front:
          _front?.dispose();
          _front = img;
          _frontStale = false;
        case _JobKind.cassette:
          _cassette?.dispose();
          _cassette = img;
          _cassetteFor = job.progress;
          _cassetteStale = false;
        case _JobKind.frame:
          _frames.put(job.frame, img);
          _stale.remove(job.frame);
      }
      notifyListeners();
    }
  }

  Future<ui.Image?> _composite(PlateSpec? spec, double scale) async {
    final atlas = _atlas;
    if (spec == null || atlas == null) return null;
    final s = scale.clamp(0.3, 1.0);
    final size = Size((spec.size.width * s).roundToDouble(),
        (spec.size.height * s).roundToDouble());
    // Our own handle first: setAtlas may replace the atlas while we wait.
    final art = atlas.clone();
    PlateImages? images;
    try {
      images = await _sources.acquirePlate(spec);
      return await compositor.renderPlate(images, art, size);
    } catch (e) {
      debugPrint('Hero plate ${spec.key} failed: $e');
      return null;
    } finally {
      images?.dispose();
      art.dispose();
      // The result is all we keep; drop the 3 source images right away.
      _sources.evictPlate(spec);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    _frames.clear();
    _atlas?.dispose();
    _front?.dispose();
    _cassette?.dispose();
    _sources.clear();
    super.dispose();
  }
}

enum _JobKind { frame, front, cassette }

/// One composition. Typed, because on the web an int frame index and a
/// double progress are the same number and `is double` cannot tell them
/// apart.
@immutable
class _Job {
  const _Job.frame(this.frame)
      : kind = _JobKind.frame,
        progress = 0;
  const _Job.front()
      : kind = _JobKind.front,
        frame = 0,
        progress = 0;
  const _Job.cassette(this.progress)
      : kind = _JobKind.cassette,
        frame = 0;

  final _JobKind kind;
  final int frame;
  final double progress;

  @override
  bool operator ==(Object other) =>
      other is _Job &&
      other.kind == kind &&
      other.frame == frame &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(kind, frame, progress);
}
