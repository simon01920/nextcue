import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Decodes [provider] at the smallest size that still *covers* a
/// [width] x [height] (device pixels) box, preserving aspect ratio and never
/// upscaling.
///
/// [ResizeImage] only offers exact or "fit inside" sizing; for
/// `BoxFit.cover` slots both under-sample (blurry) whenever the image is
/// wider or taller than the slot. Covering decodes keep artwork sharp while
/// a 1920x1080 TVDB background shown in a 360 px card decodes at about
/// 1/16th of the memory.
@immutable
class CoverResizeImage extends ImageProvider<CoverResizeKey> {
  const CoverResizeImage(this.provider,
      {required this.width, required this.height});

  final ImageProvider provider;
  final int width;
  final int height;

  @override
  Future<CoverResizeKey> obtainKey(ImageConfiguration configuration) async {
    final inner = await provider.obtainKey(configuration);
    return CoverResizeKey._(inner, width, height);
  }

  @override
  ImageStreamCompleter loadImage(
      CoverResizeKey key, ImageDecoderCallback decode) {
    Future<ui.Codec> decodeCover(ui.ImmutableBuffer buffer,
        {ui.TargetImageSizeCallback? getTargetSize}) {
      return decode(buffer, getTargetSize: (iw, ih) {
        if (iw <= 0 || ih <= 0) return const ui.TargetImageSize();
        final scale = math.max(width / iw, height / ih);
        if (scale >= 1) return const ui.TargetImageSize();
        return ui.TargetImageSize(
          width: math.max(1, (iw * scale).ceil()),
          height: math.max(1, (ih * scale).ceil()),
        );
      });
    }

    return provider.loadImage(key._inner, decodeCover);
  }
}

@immutable
class CoverResizeKey {
  const CoverResizeKey._(this._inner, this._width, this._height);
  final Object _inner;
  final int _width;
  final int _height;

  @override
  bool operator ==(Object other) =>
      other is CoverResizeKey &&
      other._inner == _inner &&
      other._width == _width &&
      other._height == _height;

  @override
  int get hashCode => Object.hash(_inner, _width, _height);
}
