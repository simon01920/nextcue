import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Where the user is with a title — drives the sticker language on the
/// spine, the hero spine and the cassette labels (see docs/LABELS.md).
enum TapeStateKind { notStarted, watching, completed, newEpisode }

/// Viewing state of one tape.
@immutable
class TapeState {
  const TapeState({
    required this.kind,
    this.progress = 0,
    this.watched = 0,
    this.total = 0,
    this.nextCode,
  });

  const TapeState.notStarted({int total = 0})
      : this(kind: TapeStateKind.notStarted, total: total);

  const TapeState.completed({int total = 0})
      : this(
          kind: TapeStateKind.completed,
          progress: 1,
          watched: total,
          total: total,
        );

  final TapeStateKind kind;

  /// 0..1 (watched / aired).
  final double progress;

  /// Episodes watched.
  final int watched;

  /// Aired episodes (0 for movies).
  final int total;

  /// e.g. "S02 E05" for watching / newEpisode.
  final String? nextCode;

  /// Stable textual identity, used by [TapeLabelData.cacheKey].
  String get cacheKey =>
      '${kind.name}:${progress.toStringAsFixed(3)}:$watched/$total:${nextCode ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is TapeState &&
      other.kind == kind &&
      other.progress == progress &&
      other.watched == watched &&
      other.total == total &&
      other.nextCode == nextCode;

  @override
  int get hashCode => Object.hash(kind, progress, watched, total, nextCode);

  @override
  String toString() => 'TapeState($cacheKey)';
}

/// Everything the label composer needs to print one tape.
/// Everything the label composer needs to print one tape.
///
/// Artwork (all optional, each with a designed fallback):
/// * [poster] → front cover (and the poster-art spine style);
/// * [logo] → spine title (rotated), over busy/missing front art, cassette;
/// * [background] (TVDB fanart, landscape) → back cover hero image, stills,
///   cassette face;
/// * [banner] (TVDB 758×140 wide banner) → cassette spine sticker.
@immutable
class TapeLabelData {
  const TapeLabelData({
    required this.titleId,
    required this.title,
    required this.state,
    this.year,
    this.isMovie = false,
    this.poster,
    this.logo,
    this.banner,
    this.background,
    this.synopsis,
    this.genres = const <String>[],
    this.network,
    this.runtime,
  });

  /// Deterministic style seed, e.g. "series-81189".
  final String titleId;

  /// May be long, may contain Slovak/Czech diacritics.
  final String title;

  /// "2014".
  final String? year;
  final bool isMovie;

  /// Portrait poster (~680×1000), may be null.
  final ui.Image? poster;

  /// Transparent clear logo, optional.
  final ui.Image? logo;

  /// Wide banner (TVDB 758×140), optional.
  final ui.Image? banner;

  /// Landscape background / fanart (TVDB ~1920×1080), optional.
  final ui.Image? background;
  final String? synopsis;
  final List<String> genres;

  /// "AMC", "Netflix"…
  final String? network;

  /// "47 min" / "2h 12m".
  final String? runtime;
  final TapeState state;

  /// A string that changes whenever the printed atlas would change. Images
  /// are keyed by their size and identity hash, so a cache keyed on this
  /// must be scoped to the lifetime of the images it was built from.
  String get cacheKey {
    final b = StringBuffer()
      ..write(titleId)
      ..write('|')
      ..write(title)
      ..write('|')
      ..write(year ?? '')
      ..write('|')
      ..write(isMovie ? 'm' : 's')
      ..write('|')
      ..write(_imageKey(poster))
      ..write('|')
      ..write(_imageKey(logo))
      ..write('|')
      ..write(_imageKey(banner))
      ..write('|')
      ..write(_imageKey(background))
      ..write('|')
      ..write(synopsis?.hashCode ?? 0)
      ..write('|')
      ..write(genres.join(','))
      ..write('|')
      ..write(network ?? '')
      ..write('|')
      ..write(runtime ?? '')
      ..write('|')
      ..write(state.cacheKey);
    return b.toString();
  }

  static String _imageKey(ui.Image? img) => img == null
      ? '-'
      : '${img.width}x${img.height}#${identityHashCode(img)}';

  /// A copy with some fields replaced. Images can be dropped with the
  /// `clear…` flags (a plain `null` means "keep").
  TapeLabelData copyWith({
    String? title,
    TapeState? state,
    String? year,
    bool? isMovie,
    ui.Image? poster,
    ui.Image? logo,
    ui.Image? banner,
    ui.Image? background,
    String? synopsis,
    List<String>? genres,
    String? network,
    String? runtime,
    bool clearPoster = false,
    bool clearLogo = false,
    bool clearBanner = false,
    bool clearBackground = false,
  }) =>
      TapeLabelData(
        titleId: titleId,
        title: title ?? this.title,
        state: state ?? this.state,
        year: year ?? this.year,
        isMovie: isMovie ?? this.isMovie,
        poster: clearPoster ? null : (poster ?? this.poster),
        logo: clearLogo ? null : (logo ?? this.logo),
        banner: clearBanner ? null : (banner ?? this.banner),
        background: clearBackground ? null : (background ?? this.background),
        synopsis: synopsis ?? this.synopsis,
        genres: genres ?? this.genres,
        network: network ?? this.network,
        runtime: runtime ?? this.runtime,
      );

  @override
  bool operator ==(Object other) =>
      other is TapeLabelData &&
      other.titleId == titleId &&
      other.title == title &&
      other.year == year &&
      other.isMovie == isMovie &&
      identical(other.poster, poster) &&
      identical(other.logo, logo) &&
      identical(other.banner, banner) &&
      identical(other.background, background) &&
      other.synopsis == synopsis &&
      listEquals(other.genres, genres) &&
      other.network == network &&
      other.runtime == runtime &&
      other.state == state;

  @override
  int get hashCode => Object.hash(
        titleId,
        title,
        year,
        isMovie,
        poster == null ? 0 : identityHashCode(poster),
        logo == null ? 0 : identityHashCode(logo),
        banner == null ? 0 : identityHashCode(banner),
        background == null ? 0 : identityHashCode(background),
        synopsis,
        Object.hashAll(genres),
        network,
        runtime,
        state,
      );

  @override
  String toString() => 'TapeLabelData($titleId, "$title", $state)';
}