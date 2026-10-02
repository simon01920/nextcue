import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../theme/tokens.dart';

/// The favourites shelf: each favourite is a worn VHS box rendered in 3D
/// (spine + front face) from the bundled cassette texture atlas and TVDB
/// art — banner on the spine, background + clear logo on the front.
/// Tapping a box ejects the cassette (label carries the logo), per the
/// reference video. Free accounts shelve up to
/// [AppState.favoriteLimitFree] tapes.
///
/// The bundled glTF models in assets/vhs/source are used as visual
/// reference only — glTF runtime rendering isn't cross-platform in
/// Flutter (webview-based viewers don't run on Windows), so the box is
/// built from transforms + the atlas textures instead.
class VhsShelf extends StatelessWidget {
  final List<String> ids;
  const VhsShelf({super.key, required this.ids});

  static const double frontW = 132;
  static const double caseH = 208;
  static const double spineD = 30;
  static const double angle = 1.05; // ~60°

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Text('Tap the heart on a show or movie to shelve its tape.',
            style: AppTextStyles.subtitle),
      );
    }
    // reverse:true + reversed ids keeps display order while letting each
    // box overlap the one behind it to the right.
    final ordered = ids.reversed.toList();
    return SizedBox(
      height: caseH + 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        itemCount: ordered.length,
        itemExtent: spineD * 0.87 + frontW * math.cos(angle) + 10,
        itemBuilder: (context, i) => _ShelvedVhs(id: ordered[i]),
      ),
    );
  }
}

/// One favourite: loads title + brand art, renders the angled 3D box,
/// opens the eject dialog on tap.
class _ShelvedVhs extends StatelessWidget {
  final String id;
  const _ShelvedVhs({required this.id});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    return FutureBuilder<(MediaTitle, BrandArt)>(
      future: () async {
        final t = await repo.titleById(id);
        final art = await repo.brandArt(id);
        return (t, art);
      }(),
      builder: (context, snap) {
        final data = snap.data;
        return GestureDetector(
          onTap: data == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  showGeneralDialog<void>(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: 'vhs',
                    barrierColor: AppColors.overlayScrim,
                    transitionDuration: AppMotion.slide,
                    pageBuilder: (_, __, ___) =>
                        _VhsEjectDialog(title: data.$1, art: data.$2),
                  );
                },
          child: _Vhs3DBox(
            title: data?.$1,
            art: data?.$2,
          ),
        );
      },
    );
  }
}

/// Two joined faces sharing a hinge: the spine (left, near head-on) and
/// the front cover (sweeping away to the right).
class _Vhs3DBox extends StatelessWidget {
  final MediaTitle? title;
  final BrandArt? art;
  const _Vhs3DBox({required this.title, required this.art});

  @override
  Widget build(BuildContext context) {
    const spineTilt = VhsShelf.angle - math.pi / 2; // ~-30°
    return Center(
      child: SizedBox(
        width: VhsShelf.spineD + VhsShelf.frontW,
        height: VhsShelf.caseH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Spine: pivots on its right edge (the box corner).
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: VhsShelf.spineD,
              child: Transform(
                alignment: Alignment.centerRight,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0022)
                  ..rotateY(spineTilt),
                child: _VhsSpine(title: title),
              ),
            ),
            // Front cover: pivots on its left edge (same corner).
            Positioned(
              left: VhsShelf.spineD,
              top: 0,
              bottom: 0,
              width: VhsShelf.frontW,
              child: Transform(
                alignment: Alignment.centerLeft,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0022)
                  ..rotateY(VhsShelf.angle),
                child: _VhsFront(title: title, art: art),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spine: TVDB banner cropped to the strip, VHS branding, worn overlay.
class _VhsSpine extends StatelessWidget {
  final MediaTitle? title;
  const _VhsSpine({required this.title});

  @override
  Widget build(BuildContext context) {
    final banner = title?.banner ?? title?.poster;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x80000000), blurRadius: 8, offset: Offset(2, 5)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: banner != null && banner.startsWith('http')
                ? RotatedBox(
                    quarterTurns: 1,
                    child: _WornImage(url: banner),
                  )
                : ColoredBox(
                    color: const Color(0xFF1E1E1E),
                    child: Center(
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Text(
                          title?.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.microCaps
                              .copyWith(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
          ),
          // Spine base cap with the format branding.
          Container(
            height: 22,
            color: const Color(0xF20D0D0D),
            alignment: Alignment.center,
            child: const Text(
              'VHS',
              style: TextStyle(
                fontFamily: AppTextStyles.uiFamily,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                fontStyle: FontStyle.italic,
                letterSpacing: 2,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Front cover: background art, clear logo (or styled title), branding
/// strip and wear.
class _VhsFront extends StatelessWidget {
  final MediaTitle? title;
  final BrandArt? art;
  const _VhsFront({required this.title, required this.art});

  @override
  Widget build(BuildContext context) {
    final bg = art?.background ?? title?.poster;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(
              color: Color(0x99000000), blurRadius: 12, offset: Offset(6, 7)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bg != null && bg.startsWith('http'))
            _WornImage(url: bg)
          else
            const ColoredBox(color: Color(0xFF1E1E1E)),
          // Cover shading: darker toward the base like sun-faded card.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.55, 1],
                colors: [
                  Color(0x33000000),
                  Color(0x14000000),
                  Color(0xA6000000),
                ],
              ),
            ),
          ),
          // Clear logo (or styled name) in the upper third.
          Positioned(
            left: 8,
            right: 8,
            top: 14,
            child: _ClearLogo(title: title, art: art, height: 44),
          ),
          // Bottom branding strip.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 24,
              color: const Color(0xF20D0D0D),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('VHS',
                      style: TextStyle(
                        fontFamily: AppTextStyles.uiFamily,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 2,
                        color: Colors.white70,
                      )),
                  Text('HI-FI STEREO',
                      style: TextStyle(
                        fontFamily: AppTextStyles.uiFamily,
                        fontSize: 7,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: Colors.white38,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clear-logo image with a styled-text fallback for titles without one.
class _ClearLogo extends StatelessWidget {
  final MediaTitle? title;
  final BrandArt? art;
  final double height;
  const _ClearLogo(
      {required this.title, required this.art, required this.height});

  @override
  Widget build(BuildContext context) {
    final logo = art?.clearLogo;
    final fallback = Text(
      title?.name ?? '',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: AppTextStyles.displayFamily,
        fontSize: height * 0.34,
        height: 1.1,
        color: Colors.white,
        shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
      ),
    );
    if (logo == null) return fallback;
    return Image.network(
      logo,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

/// Network image with the worn-paper texture from the VHS atlas multiplied
/// on top, so pulled art looks like it aged on the sleeve.
class _WornImage extends StatelessWidget {
  final String url;
  const _WornImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF1E1E1E))),
        const Opacity(
          opacity: 0.3,
          child: _AtlasSprite(
            src: _VhsAtlas.labelPaper,
            blendMode: BlendMode.multiply,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Eject dialog — the cassette slides out of the sleeve.
// ---------------------------------------------------------------------------

class _VhsEjectDialog extends StatefulWidget {
  final MediaTitle title;
  final BrandArt art;
  const _VhsEjectDialog({required this.title, required this.art});

  @override
  State<_VhsEjectDialog> createState() => _VhsEjectDialogState();
}

class _VhsEjectDialogState extends State<_VhsEjectDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _buzzed = false;

  static const double _boxW = 210;
  static const double _boxH = 330;
  static const double _tapeW = 190;
  static const double _tapeH = 112;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..addListener(() {
        if (!_buzzed && _ctrl.value > 0.96) {
          _buzzed = true;
          HapticFeedback.mediumImpact();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: IconButton(
              icon: Icon(Icons.close,
                  color: AppColors.textPrimary, size: 26),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                // Phase 1: sleeve settles straight. Phase 2: tape ejects.
                final settle = Curves.easeOutCubic
                    .transform((_ctrl.value / 0.35).clamp(0.0, 1.0));
                final eject = Curves.easeOutBack.transform(
                    ((_ctrl.value - 0.35) / 0.65).clamp(0.0, 1.0));
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: _boxW + 60,
                      height: _boxH + _tapeH * 0.9 + 20,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          // The cassette slides down from behind the sleeve.
                          Positioned(
                            top: _boxH - _tapeH + eject * _tapeH * 0.85,
                            child: Transform.rotate(
                              angle: (1 - eject) * -0.05,
                              child: _Cassette(
                                title: widget.title,
                                art: widget.art,
                                width: _tapeW,
                                height: _tapeH,
                              ),
                            ),
                          ),
                          // The sleeve, settling from a slight 3D tilt.
                          Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0016)
                              ..rotateY((1 - settle) * 0.6),
                            child: SizedBox(
                              width: _boxW,
                              height: _boxH,
                              child: _VhsFront(
                                  title: widget.title, art: widget.art),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(widget.title.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.sectionHeader
                            .copyWith(fontSize: 20)),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxl,
                            vertical: AppSpacing.md),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push(
                            '/${widget.title.kind == MediaKind.movie ? 'movie' : 'series'}/${widget.title.id}');
                      },
                      child: Text('OPEN',
                          style: AppTextStyles.buttonPillCaps),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The ejected cassette: atlas shell (spools + windows) with the worn
/// paper label carrying the clear logo / title.
class _Cassette extends StatelessWidget {
  final MediaTitle title;
  final BrandArt art;
  final double width;
  final double height;
  const _Cassette({
    required this.title,
    required this.art,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
              color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Worn paper label with the show's branding.
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const _AtlasSprite(src: _VhsAtlas.labelPaper),
                Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: _CassetteLabelBrand(title: title, art: art),
                  ),
                ),
              ],
            ),
          ),
          // Cassette shell with the spool windows from the atlas.
          const Expanded(
            flex: 6,
            child: _AtlasSprite(src: _VhsAtlas.cassetteFace),
          ),
        ],
      ),
    );
  }
}

class _CassetteLabelBrand extends StatelessWidget {
  final MediaTitle title;
  final BrandArt art;
  const _CassetteLabelBrand({required this.title, required this.art});

  @override
  Widget build(BuildContext context) {
    final logo = art.clearLogo;
    final text = Text(
      title.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppTextStyles.displayFamily,
        fontSize: 15,
        color: Color(0xFF2A2119),
      ),
    );
    if (logo == null) return text;
    return Image.network(
      logo,
      height: 30,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => text,
    );
  }
}

// ---------------------------------------------------------------------------
// Texture atlas plumbing
// ---------------------------------------------------------------------------

/// Source rects inside assets/vhs/textures/None_baseColor.png (2048²).
class _VhsAtlas {
  _VhsAtlas._();
  static const String asset = 'assets/vhs/textures/None_baseColor.png';
  static const Rect cassetteFace = Rect.fromLTWH(56, 1163, 995, 484);
  static const Rect labelPaper = Rect.fromLTWH(1071, 449, 592, 403);

  static Future<ui.Image>? _image;
  static Future<ui.Image> load() => _image ??= () async {
        final data = await rootBundle.load(asset);
        final codec =
            await ui.instantiateImageCodec(data.buffer.asUint8List());
        return (await codec.getNextFrame()).image;
      }();
}

/// Draws one atlas region stretched over the widget bounds.
class _AtlasSprite extends StatelessWidget {
  final Rect src;
  final BlendMode blendMode;
  const _AtlasSprite({required this.src, this.blendMode = BlendMode.srcOver});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _VhsAtlas.load(),
      builder: (context, snap) {
        final img = snap.data;
        if (img == null) return const SizedBox.expand();
        return CustomPaint(
          painter: _AtlasPainter(image: img, src: src, blendMode: blendMode),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _AtlasPainter extends CustomPainter {
  final ui.Image image;
  final Rect src;
  final BlendMode blendMode;
  _AtlasPainter(
      {required this.image, required this.src, required this.blendMode});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()
        ..blendMode = blendMode
        ..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_AtlasPainter old) =>
      old.image != image || old.src != src || old.blendMode != blendMode;
}
