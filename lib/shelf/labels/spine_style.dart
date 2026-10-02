import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'label_art.dart';
import 'label_palette.dart';
import 'label_rng.dart';
import 'label_text.dart';
import 'label_wear.dart';
import 'tape_label_data.dart';
import 'title_fitter.dart';

/// The spine designs a tape can be printed with.
enum SpineStyleKind {
  /// Black spine, large condensed title, a coloured band.
  blackBand,

  /// Vertical crop of the poster under a dark gradient, title in a box.
  posterArt,

  /// White minimal spine with hairline rules.
  paperRules,

  /// Bold stacked colour blocks.
  colourBlock,

  /// Rental-store spine with a diagonal stripe header.
  rentalStripe,

  /// Night-sky gradient, striped synth sun band, chrome title.
  synthChrome,

  /// Cream or black spine with thin retro rainbow stripes.
  rainbow,
}

/// Deterministic per-title design decisions. Depends only on the title id
/// (never on the poster), so a tape keeps its design when art loads.
@immutable
class SpineStyleSpec {
  const SpineStyleSpec({
    required this.kind,
    required this.variant,
    required this.markAtTop,
    required this.band,
    required this.band2,
    required this.catalogue,
    required this.focusX,
    required this.swapAccents,
    required this.titleAlign,
    required this.stickerShift,
    required this.stickerTilt,
    required this.wear,
    this.markStyle = 0,
  });

  factory SpineStyleSpec.forTitle(String titleId) {
    final r = LabelRng.forTitle(titleId, 'spine-style');
    final kind = SpineStyleKind.values[r.nextInt(SpineStyleKind.values.length)];
    return SpineStyleSpec(
      kind: kind,
      variant: r.nextInt(4),
      markAtTop: r.chance(0.68),
      band: r.nextDouble(),
      band2: r.nextDouble(),
      catalogue: 1000 + r.nextInt(9000),
      focusX: r.range(-0.7, 0.7),
      swapAccents: r.chance(0.35),
      titleAlign: r.pick(const [
        TitleAlign.center,
        TitleAlign.center,
        TitleAlign.start,
        TitleAlign.end,
      ]),
      stickerShift: r.range(-1, 1),
      stickerTilt: r.range(-0.085, 0.085),
      wear: LabelWear.levelFor(titleId),
      markStyle: r.nextInt(3),
    );
  }

  final SpineStyleKind kind;

  /// 0..3 sub-variant (band position, stripe count, colour order…).
  final int variant;

  /// Studio mark at the top (else at the foot).
  final bool markAtTop;

  /// 0..1 free parameters for band heights / split positions.
  final double band, band2;

  /// Catalogue number printed on the spine and back.
  final int catalogue;

  /// −1..1 horizontal focus of the poster slice.
  final double focusX;

  /// Use accent2 as the lead colour.
  final bool swapAccents;

  /// Title alignment along the spine.
  final TitleAlign titleAlign;

  /// −1..1 sticker position jitter.
  final double stickerShift;

  /// Sticker rotation, radians.
  final double stickerTilt;

  /// Shelf wear 0..1.
  final double wear;

  /// Studio mark treatment: 0 disc + wordmark, 1 boxed lockup, 2 disc.
  final int markStyle;

  @override
  bool operator ==(Object other) =>
      other is SpineStyleSpec &&
      other.kind == kind &&
      other.variant == variant &&
      other.markAtTop == markAtTop &&
      other.band == band &&
      other.band2 == band2 &&
      other.catalogue == catalogue &&
      other.focusX == focusX &&
      other.swapAccents == swapAccents &&
      other.titleAlign == titleAlign &&
      other.stickerShift == stickerShift &&
      other.stickerTilt == stickerTilt &&
      other.wear == wear &&
      other.markStyle == markStyle;

  @override
  int get hashCode => Object.hash(kind, variant, markAtTop, band, band2,
      catalogue, focusX, swapAccents, titleAlign, stickerShift, stickerTilt, wear,
      markStyle);

  @override
  String toString() =>
      'SpineStyleSpec(${kind.name} v$variant, mark ${markAtTop ? 'top' : 'foot'}, '
      'cat $catalogue, wear ${wear.toStringAsFixed(2)})';
}

/// Everything a surface painter needs for one tape.
class LabelContext {
  LabelContext({
    required this.data,
    required this.palette,
    required this.style,
    required this.grain,
    required this.speckle,
    this.logoInfo,
    this.posterDetail = 0,
    this.recorder,
  });

  final TapeLabelData data;
  final TapePalette palette;
  final SpineStyleSpec style;

  /// Neutral grain tile (overlay).
  final ui.Image grain;

  /// Speck alpha mask (ink erosion).
  final ui.Image speckle;

  /// Sampled colour of the clear logo (null without a logo).
  final LogoInfo? logoInfo;

  /// How busy the poster is (see [PosterSwatch.detail]); 0 without one.
  final double posterDetail;
  final TextRecorder? recorder;

  LabelContext copyWith({TapePalette? palette, bool dropRecorder = false}) =>
      LabelContext(
        data: data,
        palette: palette ?? this.palette,
        style: style,
        grain: grain,
        speckle: speckle,
        logoInfo: logoInfo,
        posterDetail: posterDetail,
        recorder: dropRecorder ? null : recorder,
      );

  /// The clear logo, if any.
  ui.Image? get logo => data.logo;

  LabelRng rng(String salt) => LabelRng.forTitle(data.titleId, salt);

  /// Wear actually printed: a tape that was never opened (still
  /// shrink-wrapped on the shelf) is near-mint.
  double get wear => data.state.kind == TapeStateKind.notStarted
      ? style.wear * 0.12
      : style.wear;

  /// Lead / second colour after the style's swap.
  Color get lead => style.swapAccents ? palette.accent2 : palette.accent;
  Color get second => style.swapAccents ? palette.accent : palette.accent2;

  String get catalogueNo =>
      '${data.isMovie ? 'NCM' : 'NCS'}-${style.catalogue}';

  void region(String name) => recorder?.region = name;
}
