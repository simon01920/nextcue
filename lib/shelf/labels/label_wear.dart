import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'label_palette.dart';
import 'label_rng.dart';

/// Which edges of a printed surface are folds (they rub the most).
class WearEdges {
  const WearEdges({
    this.left = 1,
    this.top = 1,
    this.right = 1,
    this.bottom = 1,
  });

  /// Relative rub per edge (0 = none, 1 = normal, >1 = fold).
  final double left, top, right, bottom;
}

/// Deterministic shelf wear: print rubbed off along folds and corners
/// (light board showing through) and a slight overall fade. Subtle by
/// design; confined to a few millimetres of the edges so it never
/// reaches the title.
class LabelWear {
  LabelWear._();

  /// Per-title wear level 0..1, skewed towards gently used.
  static double levelFor(String titleId) {
    final r = LabelRng.forTitle(titleId, 'wear-level');
    final x = r.nextDouble();
    return 0.12 + 0.78 * x * x;
  }

  /// Max depth (design units) that scuffs reach in from an edge.
  static const double maxDepth = 24;

  static final Paint _dot = Paint()..strokeCap = StrokeCap.round;
  static final Paint _fill = Paint();

  /// Paints wear over [rect] (already painted). [salt] makes each surface
  /// independent ("spine", "front"…).
  static void paint(
    Canvas canvas,
    Rect rect, {
    required String titleId,
    required String salt,
    required double level,
    WearEdges edges = const WearEdges(),
    Color board = LabelColors.board,
    double fade = 1,
  }) {
    if (level <= 0) return;
    final rng = LabelRng.forTitle(titleId, 'wear-$salt');
    canvas.save();
    canvas.clipRect(rect);

    // Slight fade: the print lost a little density.
    _fill
      ..blendMode = BlendMode.screen
      ..color = Color.fromRGBO(236, 228, 210, (0.025 + 0.06 * level) * fade);
    canvas.drawRect(rect, _fill);
    _fill.blendMode = BlendMode.srcOver;

    // Scuff buckets (short strokes running along the edge, as rubbing
    // makes them): 3 widths × 3 alphas.
    final buckets = List<List<double>>.generate(9, (_) => <double>[]);
    void edge(Offset a, Offset b, Offset inward, double weight) {
      if (weight <= 0) return;
      final len = (b - a).distance;
      final dir = (b - a) / len;
      // Rubbed patches: clusters of strokes, more of them near corners.
      final clusters = (len / 160 * (0.6 + 2.4 * level) * weight).round();
      for (var k = 0; k < clusters; k++) {
        var t = rng.nextDouble();
        if (rng.chance(0.4)) {
          t = rng.chance(0.5) ? t * t * 0.2 : 1 - t * t * 0.2;
        }
        final extent = rng.range(14, 70) * (0.6 + level);
        final strokes = 3 + rng.nextInt(4 + (8 * level).round());
        for (var i = 0; i < strokes; i++) {
          final along = (t * len + rng.jitter(extent / 2)).clamp(0.0, len);
          final dT = rng.nextDouble();
          final depth = dT * dT * maxDepth * (0.25 + 0.45 * level);
          final l = rng.range(2.5, 9 + 10 * level) * (1 - depth / maxDepth * 0.6);
          final p0 = a + dir * along + inward * depth;
          final p1 = p0 + dir * l + inward * rng.jitter(0.8);
          final w = depth < 3 ? (rng.chance(0.6) ? 2 : 1) : rng.nextInt(2);
          final alpha = depth < 3 ? 2 : (depth < 9 ? 1 : 0);
          buckets[w * 3 + alpha].addAll([p0.dx, p0.dy, p1.dx, p1.dy]);
        }
      }
      // Hairline crack along the fold where the ink split: irregular runs
      // of varying length, gap, weight and inset (never a regular dash).
      final runs = List<List<double>>.generate(3, (_) => <double>[]);
      final continuity = (0.18 + 0.55 * level) * math.min(1.0, weight * 0.75);
      var pos = rng.range(0, 20);
      while (pos < len) {
        final run = rng.range(5, 18 + 46 * continuity);
        final gap = rng.range(3, 40 * (1.1 - continuity));
        if (rng.chance(0.35 + 0.6 * continuity)) {
          final end = math.min(len, pos + run);
          final i0 = rng.range(0.3, 2.4), i1 = rng.range(0.3, 2.4);
          final p0 = a + dir * pos + inward * i0;
          final p1 = a + dir * end + inward * i1;
          runs[rng.nextInt(3)].addAll([p0.dx, p0.dy, p1.dx, p1.dy]);
        }
        pos += run + gap;
      }
      for (var k = 0; k < 3; k++) {
        if (runs[k].isEmpty) continue;
        _dot
          ..color = board.withValues(alpha: (0.3 + 0.22 * k) * (0.7 + 0.4 * level))
          ..strokeWidth = 1.2 + 0.8 * k;
        canvas.drawRawPoints(
            ui.PointMode.lines, Float32List.fromList(runs[k]), _dot);
      }
    }

    edge(rect.topLeft, rect.bottomLeft, const Offset(1, 0), edges.left);
    edge(rect.topRight, rect.bottomRight, const Offset(-1, 0), edges.right);
    edge(rect.topLeft, rect.topRight, const Offset(0, 1), edges.top);
    edge(rect.bottomLeft, rect.bottomRight, const Offset(0, -1), edges.bottom);

    const widths = [1.3, 2.2, 3.4];
    const alphas = [0.3, 0.55, 0.85];
    for (var s = 0; s < 3; s++) {
      for (var a = 0; a < 3; a++) {
        final pts = buckets[s * 3 + a];
        if (pts.isEmpty) continue;
        _dot
          ..color = board.withValues(alpha: alphas[a])
          ..strokeWidth = widths[s];
        canvas.drawRawPoints(
            ui.PointMode.lines, Float32List.fromList(pts), _dot);
      }
    }

    // Corner chips: small irregular blobs where two edges meet.
    void corner(Offset c, Offset ix, Offset iy, double w) {
      if (w <= 0 || !rng.chance(0.35 + 0.6 * level)) return;
      final r = rng.range(5, 12 + 22 * level) * math.min(1.3, w);
      final path = Path();
      const n = 9;
      for (var i = 0; i <= n; i++) {
        final ang = i / n * math.pi / 2;
        final rr = r * rng.range(0.55, 1.0);
        final p = c + ix * (math.cos(ang) * rr) + iy * (math.sin(ang) * rr);
        if (i == 0) {
          path.moveTo(c.dx, c.dy);
        }
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      _fill.color = board.withValues(alpha: 0.6 + 0.3 * level);
      canvas.drawPath(path, _fill);
    }

    corner(rect.topLeft, const Offset(1, 0), const Offset(0, 1),
        math.min(edges.left, edges.top));
    corner(rect.topRight, const Offset(-1, 0), const Offset(0, 1),
        math.min(edges.right, edges.top));
    corner(rect.bottomLeft, const Offset(1, 0), const Offset(0, -1),
        math.min(edges.left, edges.bottom));
    corner(rect.bottomRight, const Offset(-1, 0), const Offset(0, -1),
        math.min(edges.right, edges.bottom));

    canvas.restore();
  }
}
