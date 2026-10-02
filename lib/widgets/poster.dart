import 'package:flutter/material.dart';

import '../theme/tokens.dart';

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
      child = Image.network(
        src,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (c, w, progress) =>
            progress == null ? w : _placeholder(),
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
