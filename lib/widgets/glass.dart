import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Bingely "liquid glass" material — the shared surface behind the bottom
/// nav, segmented tabs and the Decide wheel chrome (Tasks 1/3/5).
///
/// Cross-platform contract (Task 6): built on Flutter's own compositor
/// (BackdropFilter + ContinuousRectangleBorder), so the exact same code
/// renders the blur on iOS, Android, Windows and web/CanvasKit — no
/// iOS-only APIs. Where a backdrop blur cannot run (e.g. the legacy HTML
/// web renderer silently no-ops it), the fill below is deliberately
/// substantial enough that the surface degrades to a translucent
/// smoked-glass panel instead of looking broken.
class AppGlass {
  AppGlass._();

  static const double blurSigma = 24;

  /// Continuous-corner ("squircle") radii. ContinuousRectangleBorder draws
  /// iOS-style superellipse corners rather than circular CSS-like arcs.
  static const double radiusPill = 40;
  static const double radiusPanel = 28;

  /// Multiplier from nominal radius to ContinuousRectangleBorder radius —
  /// higher reads rounder/softer.
  static const double squircle = 2.2;

  // Dark theme fills.
  static const Color fillDark = Color(0xB31A1A1A); // ~70% smoked glass
  static const Color strokeDark = Color(0x2EFFFFFF);
  static const Color specularDark = Color(0x24FFFFFF);

  // Light theme fills.
  static const Color fillLight = Color(0xB8F4F4F4);
  static const Color strokeLight = Color(0x33FFFFFF);
  static const Color specularLight = Color(0x66FFFFFF);

  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

/// A frosted, squircle-cornered glass surface: blurs whatever scrolls
/// behind it, tints it with a translucent fill, and adds a hairline stroke
/// plus a top specular highlight so the material reads as lit glass.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final bool shadow;

  /// True renders a StadiumBorder — a perfect capsule with fully round
  /// ends. Use for bar-shaped surfaces (bottom nav, segmented tabs);
  /// ContinuousRectangleBorder flattens ("čapatý") and can draw edge
  /// artifacts once its radius approaches the surface height.
  final bool stadium;

  const GlassSurface({
    super.key,
    required this.child,
    this.radius = AppGlass.radiusPanel,
    this.padding,
    this.fill,
    this.shadow = false,
    this.stadium = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final OutlinedBorder shape = stadium
        ? const StadiumBorder()
        : ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(radius * AppGlass.squircle),
          );
    return Container(
      decoration: shadow
          ? ShapeDecoration(shape: shape, shadows: AppGlass.lift)
          : null,
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        // Grouped: glass surfaces on screen together (bottom nav, top tabs)
        // share one backdrop read under the app-wide BackdropGroup instead
        // of each copying and blurring the screen behind it every frame.
        // Without a group it behaves like a plain BackdropFilter.
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(
              sigmaX: AppGlass.blurSigma, sigmaY: AppGlass.blurSigma),
          child: Container(
            padding: padding,
            decoration: ShapeDecoration(
              color: fill ?? (dark ? AppGlass.fillDark : AppGlass.fillLight),
              shape: shape.copyWith(
                side: BorderSide(
                  color: dark ? AppGlass.strokeDark : AppGlass.strokeLight,
                  width: 1,
                ),
              ),
            ),
            // Top-lit specular sheen over the fill, under the child.
            foregroundDecoration: ShapeDecoration(
              shape: shape,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.45, 1],
                colors: [
                  dark ? AppGlass.specularDark : AppGlass.specularLight,
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
