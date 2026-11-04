import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'cover_resize_image.dart';

/// Gradient poster/still placeholder — mirrors TV Time's own pre-load artwork
/// slot (a flat #202020 → slightly lighter gradient). When [imageAsset] is a
/// real asset it renders that; otherwise the placeholder, with an optional
/// title label so mock cards remain legible.
class Poster extends StatelessWidget {
  final String? imageAsset;
  final double? width;
  final double? height;
  final double radius;
  final String? label;
  final BoxFit fit;

  const Poster({
    super.key,
    this.imageAsset,
    this.width,
    this.height,
    this.radius = AppRadius.sm,
    this.label,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    final src = imageAsset;
    if (src != null && src.startsWith('http')) {
      // Decode at display size, not source size: TVDB posters are
      // ~680x1000 and backgrounds 1920x1080, so a grid of full-size decodes
      // costs tens of MB of image memory and janks the first scroll.
      child = LayoutBuilder(
        builder: (context, c) => _network(
          context,
          src,
          width ?? (c.hasBoundedWidth ? c.maxWidth : null),
          height ?? (c.hasBoundedHeight ? c.maxHeight : null),
        ),
      );
    } else if (src != null && src.isNotEmpty) {
      child = Image.asset(src, width: width, height: height, fit: fit);
    } else {
      child = _placeholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  Widget _network(
      BuildContext context, String src, double? slotW, double? slotH) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    // Buckets of 64 device px so near-identical slots share one decode.
    int bucket(double logical) =>
        (((logical * dpr) / 64).ceil() * 64).clamp(64, 4096);
    final ImageProvider provider;
    if (slotW != null && slotW.isFinite && slotW > 0 &&
        slotH != null && slotH.isFinite && slotH > 0) {
      provider = CoverResizeImage(NetworkImage(src),
          width: bucket(slotW), height: bucket(slotH));
    } else if (slotW != null && slotW.isFinite && slotW > 0) {
      provider = ResizeImage(NetworkImage(src),
          width: bucket(slotW), policy: ResizeImagePolicy.fit);
    } else {
      provider = NetworkImage(src);
    }
    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(),
      // Fade in once decoded instead of popping; cached images (already
      // decoded synchronously) show immediately.
      frameBuilder: (context, child, frame, wasSync) {
        if (wasSync) return child;
        return Stack(fit: StackFit.passthrough, children: [
          if (frame == null) Positioned.fill(child: _placeholder()),
          AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: child,
          ),
        ]);
      },
    );
  }

  Widget _placeholder() {
    // Follows the theme: a dark tile on a white page reads as a broken
    // image, so the placeholder tracks the neutral palette.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.isLight
              ? [AppColors.surface, AppColors.surfaceElevated]
              : const [Color(0xFF262626), Color(0xFF1A1A1A)],
        ),
      ),
      child: label == null
          ? const SizedBox.expand()
          : Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Center(
                child: Text(
                  label!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.microCaps.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
    );
  }
}
