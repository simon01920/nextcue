import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'plate_cache.dart';

/// `shaders/plate.frag`, loaded once.
class PlateShader {
  PlateShader._();

  static const String asset = 'shaders/plate.frag';
  static Future<ui.FragmentProgram?>? _program;

  /// The compiled program, or null where fragment programs are unavailable
  /// (then [PlateCompositor] falls back to the CPU path).
  static Future<ui.FragmentProgram?> load() {
    return _program ??= ui.FragmentProgram.fromAsset(asset)
        .then<ui.FragmentProgram?>((p) => p, onError: (Object e) {
      debugPrint('plate.frag unavailable, using the CPU compositor: $e');
      return null;
    });
  }
}

/// One plate drawn into an offscreen canvas.
class PlateDraw {
  const PlateDraw({
    required this.images,
    required this.dst,
    this.art,
    this.clip,
  });

  final PlateImages images;

  /// Where the whole plate image lands, in output pixels.
  final Rect dst;

  /// Label artwork for the plate's atlas; null draws the colour plate only.
  final ui.Image? art;

  /// Optional clip, in output pixels.
  final Rect? clip;

  bool get composites => art != null && images.hasLabel;
}

/// Composites plates and their label art offscreen
/// (`out = C + T(uv)·D·tint`, docs/PLATES.md).
///
/// Every canvas this records into has an identity transform in output
/// pixels, so the shader's `FlutterFragCoord` and the rects passed to it are
/// in the same space on every backend.
class PlateCompositor {
  PlateCompositor(this.program);

  /// Null selects the CPU path: the same maths in Dart on raw RGBA bytes.
  final ui.FragmentProgram? program;

  bool get usesShader => program != null;

  static Future<PlateCompositor> create() async =>
      PlateCompositor(await PlateShader.load());

  /// Renders [draws] in order onto a transparent [width]×[height] image.
  Future<ui.Image> render(int width, int height, List<PlateDraw> draws) async {
    final cpu = program == null ? await _cpuPrepare(draws, width, height) : null;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(
        rec, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    final shaders = <ui.FragmentShader>[];
    for (var i = 0; i < draws.length; i++) {
      final d = draws[i];
      if (d.clip != null) {
        canvas.save();
        canvas.clipRect(d.clip!);
      }
      if (!d.composites) {
        final src = Offset.zero &
            Size(d.images.color.width.toDouble(),
                d.images.color.height.toDouble());
        canvas.drawImageRect(
          d.images.color,
          src,
          d.dst,
          Paint()
            ..filterQuality = d.dst.width < src.width * 0.95
                ? FilterQuality.medium
                : FilterQuality.low,
        );
      } else if (cpu != null) {
        final piece = cpu[i];
        if (piece != null) canvas.drawImage(piece.image, piece.offset, Paint());
      } else {
        final shader = _shaderFor(d);
        shaders.add(shader);
        canvas.drawRect(d.dst, Paint()..shader = shader);
      }
      if (d.clip != null) canvas.restore();
    }
    final picture = rec.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
      for (final s in shaders) {
        s.dispose();
      }
      if (cpu != null) {
        for (final p in cpu) {
          p?.image.dispose();
        }
      }
    }
  }

  /// One plate on its own, scaled to [size] output pixels.
  Future<ui.Image> renderPlate(PlateImages images, ui.Image? art, Size size) {
    final w = size.width.round(), h = size.height.round();
    return render(w, h, [
      PlateDraw(
          images: images,
          art: art,
          dst: Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())),
    ]);
  }

  ui.FragmentShader _shaderFor(PlateDraw d) {
    final s = program!.fragmentShader();
    final uv = d.images.uv!;
    final tint = d.images.spec.tint;
    final floats = <double>[
      d.dst.width, d.dst.height, // uDestSize
      d.dst.left, d.dst.top, // uDestOffset
      uv.width.toDouble(), uv.height.toDouble(), // uPlateSize
      tint[0], tint[1], tint[2], // uTint
      1, // uArtEnabled
    ];
    for (var i = 0; i < floats.length; i++) {
      s.setFloat(i, floats[i]);
    }
    s.setImageSampler(0, d.images.color, filterQuality: FilterQuality.low);
    // Never filter the hi/lo bytes; the shader interpolates by hand.
    s.setImageSampler(1, uv, filterQuality: FilterQuality.none);
    s.setImageSampler(2, d.images.uv2!, filterQuality: FilterQuality.none);
    s.setImageSampler(3, d.art!, filterQuality: FilterQuality.low);
    return s;
  }

  // ---------------------------------------------------------------------
  // CPU fallback
  // ---------------------------------------------------------------------

  Future<List<_Piece?>> _cpuPrepare(
      List<PlateDraw> draws, int width, int height) async {
    final bytes = <ui.Image, Future<RgbaPixels>>{};
    Future<RgbaPixels> px(ui.Image i) => bytes[i] ??= RgbaPixels.of(i);
    final out = <_Piece?>[];
    for (final d in draws) {
      if (!d.composites) {
        out.add(null);
        continue;
      }
      var box = Rect.fromLTRB(d.dst.left.floorToDouble(),
          d.dst.top.floorToDouble(), d.dst.right.ceilToDouble(),
          d.dst.bottom.ceilToDouble());
      box = box.intersect(
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
      if (d.clip != null) {
        box = box.intersect(Rect.fromLTRB(d.clip!.left.floorToDouble(),
            d.clip!.top.floorToDouble(), d.clip!.right.ceilToDouble(),
            d.clip!.bottom.ceilToDouble()));
      }
      if (box.isEmpty) {
        out.add(null);
        continue;
      }
      final rgba = compositePixels(
        color: await px(d.images.color),
        uv: await px(d.images.uv!),
        uv2: await px(d.images.uv2!),
        art: await px(d.art!),
        tint: d.images.spec.tint,
        dst: d.dst,
        box: box,
      );
      out.add(_Piece(
          await rgba.toImage(), Offset(box.left, box.top)));
    }
    return out;
  }

  /// The shader's maths per output pixel centre of [box] (output pixels),
  /// for a plate whose image spans [dst]. Pixels whose centre falls outside
  /// [dst] stay transparent.
  @visibleForTesting
  static RgbaPixels compositePixels({
    required RgbaPixels color,
    required RgbaPixels uv,
    required RgbaPixels uv2,
    required RgbaPixels art,
    required List<double> tint,
    required Rect dst,
    required Rect box,
  }) {
    final w = box.width.round(), h = box.height.round();
    final out = Uint8List(w * h * 4);
    final pw = uv.width, ph = uv.height;
    final c = Float64List(4);
    final a = Float64List(4);
    final taps = Int32List(4);
    final weights = Float64List(4);
    for (var y = 0; y < h; y++) {
      final ly = (box.top + y + 0.5 - dst.top) / dst.height;
      if (ly < 0 || ly > 1) continue;
      for (var x = 0; x < w; x++) {
        final lx = (box.left + x + 0.5 - dst.left) / dst.width;
        if (lx < 0 || lx > 1) continue;
        color.bilinear(lx, ly, c);
        var r = c[0], g = c[1], b = c[2];
        // Manual bilinear over the data texels.
        final qx = lx * pw - 0.5, qy = ly * ph - 0.5;
        final ix = qx.floor(), iy = qy.floor();
        final fx = qx - ix, fy = qy - iy;
        final x0 = ix.clamp(0, pw - 1), x1 = (ix + 1).clamp(0, pw - 1);
        final y0 = iy.clamp(0, ph - 1), y1 = (iy + 1).clamp(0, ph - 1);
        taps[0] = (y0 * pw + x0) * 4;
        taps[1] = (y0 * pw + x1) * 4;
        taps[2] = (y1 * pw + x0) * 4;
        taps[3] = (y1 * pw + x1) * 4;
        weights[0] = (1 - fx) * (1 - fy);
        weights[1] = fx * (1 - fy);
        weights[2] = (1 - fx) * fy;
        weights[3] = fx * fy;
        double u = 0, v = 0, dd = 0;
        for (var k = 0; k < 4; k++) {
          final o = taps[k], wk = weights[k];
          u += wk * (uv.data[o] * 256 + uv2.data[o]);
          v += wk * (uv.data[o + 1] * 256 + uv2.data[o + 1]);
          dd += wk * uv.data[o + 2];
        }
        u /= 65535.0;
        v /= 65535.0;
        dd /= 255.0;
        if (dd > 0) {
          art.bilinear(u, v, a);
          r += a[0] * dd * tint[0];
          g += a[1] * dd * tint[1];
          b += a[2] * dd * tint[2];
        }
        final o = (y * w + x) * 4;
        out[o] = (r * 255 + 0.5).clamp(0, 255).toInt();
        out[o + 1] = (g * 255 + 0.5).clamp(0, 255).toInt();
        out[o + 2] = (b * 255 + 0.5).clamp(0, 255).toInt();
        out[o + 3] = (c[3] * 255 + 0.5).clamp(0, 255).toInt();
      }
    }
    return RgbaPixels(w, h, out);
  }
}

class _Piece {
  _Piece(this.image, this.offset);
  final ui.Image image;
  final Offset offset;
}

/// Premultiplied RGBA8 pixels of an image.
class RgbaPixels {
  RgbaPixels(this.width, this.height, this.data);

  final int width;
  final int height;
  final Uint8List data;

  static Future<RgbaPixels> of(ui.Image image) async {
    final b = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return RgbaPixels(image.width, image.height, b!.buffer.asUint8List());
  }

  /// Bilinear sample at normalised [u], [v] (texel centres at (i+0.5)/n,
  /// clamped to the edge), channels 0..1 into [out].
  void bilinear(double u, double v, Float64List out) {
    final x = math.min(math.max(u * width - 0.5, 0.0), width - 1.0);
    final y = math.min(math.max(v * height - 0.5, 0.0), height - 1.0);
    final x0 = x.floor(), y0 = y.floor();
    final x1 = math.min(x0 + 1, width - 1), y1 = math.min(y0 + 1, height - 1);
    final fx = x - x0, fy = y - y0;
    final o00 = (y0 * width + x0) * 4, o10 = (y0 * width + x1) * 4;
    final o01 = (y1 * width + x0) * 4, o11 = (y1 * width + x1) * 4;
    for (var k = 0; k < 4; k++) {
      final top = data[o00 + k] * (1 - fx) + data[o10 + k] * fx;
      final bot = data[o01 + k] * (1 - fx) + data[o11 + k] * fx;
      out[k] = (top * (1 - fy) + bot * fy) / 255.0;
    }
  }

  Future<ui.Image> toImage() {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        data, width, height, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}
