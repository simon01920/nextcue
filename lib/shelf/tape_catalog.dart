import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'labels/tape_label_data.dart';
import 'shelf_layout.dart';
import 'tape_source.dart';

/// The app's watch state in the tape language (docs/LABELS.md "State
/// language"). Pure functions of [AppState] and a loaded [MediaTitle].
class TapeStates {
  TapeStates._();

  /// "S02 E05".
  static String code(EpisodeRef e) =>
      'S${e.season.toString().padLeft(2, '0')} '
      'E${e.number.toString().padLeft(2, '0')}';

  /// Whether [e] has aired. Titles that carry no air dates at all (mock or
  /// legacy data) count every episode as aired.
  static bool _aired(EpisodeRef e, bool dated, DateTime now) =>
      dated ? e.airDate != null && e.airDate!.isBefore(now) : true;

  static bool _hasDates(MediaTitle t) =>
      t.seasons.any((s) => s.episodes.any((e) => e.airDate != null));

  /// The first aired, unwatched episode in season order — the same episode
  /// the watch list's swipe-to-watch marks.
  static EpisodeRef? nextEpisode(MediaTitle t, AppState s, {DateTime? now}) {
    now ??= DateTime.now();
    final dated = _hasDates(t);
    for (final season in t.seasons) {
      for (final e in season.episodes) {
        if (_aired(e, dated, now) && !s.isWatched(e.id)) return e;
      }
    }
    return null;
  }

  static TapeState stateOf(MediaTitle t, AppState s, {DateTime? now}) {
    now ??= DateTime.now();
    final status = s.statusOf(t.id);
    if (t.kind == MediaKind.movie) {
      return switch (status) {
        TrackStatus.completed => const TapeState.completed(),
        TrackStatus.watching => const TapeState(kind: TapeStateKind.watching),
        _ => const TapeState.notStarted(),
      };
    }
    final dated = _hasDates(t);
    var aired = 0, watched = 0;
    EpisodeRef? next;
    for (final season in t.seasons) {
      for (final e in season.episodes) {
        if (!_aired(e, dated, now)) continue;
        aired++;
        if (s.isWatched(e.id)) {
          watched++;
        } else {
          next ??= e;
        }
      }
    }
    if (status == TrackStatus.completed) {
      return TapeState.completed(total: aired);
    }
    if (watched == 0) return TapeState.notStarted(total: aired);
    final progress = aired == 0 ? 0.0 : watched / aired;
    final last = s.lastWatchedAt(t.id);
    // New episode: it aired after the user last watched, i.e. they were
    // caught up and the show moved on.
    final fresh = next?.airDate != null &&
        last != null &&
        next!.airDate!.isAfter(last);
    return TapeState(
      kind: fresh ? TapeStateKind.newEpisode : TapeStateKind.watching,
      progress: progress,
      watched: watched,
      total: aired,
      nextCode: next == null ? null : code(next),
    );
  }

  /// How the tape stands, from [AppState] alone (no title load), so a
  /// collection of hundreds lays out at once.
  static TapePose poseOf(String titleId, AppState s, int watchedCount) {
    final status = s.statusOf(titleId);
    if (titleId.startsWith('movie')) {
      return switch (status) {
        TrackStatus.completed => TapePose.upright,
        TrackStatus.watching => TapePose.pulled,
        _ => TapePose.sealed,
      };
    }
    if (status == TrackStatus.completed) return TapePose.upright;
    if (watchedCount == 0) return TapePose.sealed;
    if (status == TrackStatus.stopped) return TapePose.upright;
    return TapePose.pulled;
  }

  /// Watched episode count per title in one pass over the watch history.
  static Map<String, int> watchedCounts(AppState s) {
    final counts = <String, int>{};
    for (final id in s.watchHistory) {
      final i = id.indexOf(':');
      if (i <= 0) continue;
      final t = id.substring(0, i);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return counts;
  }

  static String describe(TapeState st, {required bool isMovie}) {
    switch (st.kind) {
      case TapeStateKind.notStarted:
        return 'not started';
      case TapeStateKind.completed:
        return 'completed';
      case TapeStateKind.watching:
        if (isMovie || st.total == 0) return 'watching';
        return 'watching, ${st.watched} of ${st.total} episodes'
            '${st.nextCode == null ? '' : ', next ${st.nextCode}'}';
      case TapeStateKind.newEpisode:
        return 'new episode${st.nextCode == null ? '' : ' ${st.nextCode}'}, '
            '${st.watched} of ${st.total} episodes';
    }
  }
}

/// The four pieces of real artwork a label prints (docs/LABELS.md).
enum ArtKind {
  /// Front cover.
  poster,

  /// Spine and stickers (TVDB clear logo).
  logo,

  /// Cassette spine sticker.
  banner,

  /// Back cover and cassette face (fanart).
  background,
}

/// [TapeSource] backed by the app's repository and [AppState]: titles,
/// TVDB artwork (resolved through the same [ImageProvider]s and image cache
/// as the app's poster widgets) and watch state.
class TapeCatalog extends ChangeNotifier implements TapeSource {
  TapeCatalog({required this.repo, required this.appState}) {
    appState.addListener(_onAppState);
  }

  final ContentRepository repo;
  final AppState appState;

  /// Decode widths (px) per artwork and atlas, so memory stays bounded:
  /// the shelf atlas is ~150 px wide (spine + a 20 mm front strip) and
  /// needs only poster and logo; the hero atlas is 1536 px (front ≈ 640 px,
  /// back ≈ 640 × 1140, cassette spine sticker ≈ 880 px).
  ///
  /// Decoded sizes: shelf poster 340×500 = 0.7 MB, shelf logo ≤ 400×155 =
  /// 0.25 MB; hero poster 680×1000 = 2.7 MB, logo 800×310 = 1 MB, banner
  /// 760×140 = 0.4 MB, background 960×540 = 2.1 MB (≈ 6.2 MB per inspected
  /// title, released as soon as its atlas is composed).
  static const Map<ArtKind, (int, int)> decodeWidth = {
    ArtKind.poster: (340, 680),
    ArtKind.logo: (400, 800),
    ArtKind.banner: (0, 760),
    ArtKind.background: (0, 960),
  };

  final Map<String, MediaTitle> _titles = {};
  final Map<String, Future<MediaTitle?>> _titleLoads = {};
  final Map<String, BrandArt> _brand = {};
  final Map<String, Future<BrandArt?>> _brandLoads = {};
  final Set<String> _imagesReady = {};
  final Set<String> _imagesFailed = {};
  final Map<String, TapeState> _states = {};
  int _statesRevision = -1;
  bool _disposed = false;

  MediaTitle? title(String id) => _titles[id];

  void _onAppState() {
    _states.clear();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<MediaTitle?> loadTitle(String id) {
    final have = _titles[id];
    if (have != null) return Future.value(have);
    return _titleLoads[id] ??= repo.titleById(id).then<MediaTitle?>((t) {
      _titles[id] = t;
      _notify();
      return t;
    }, onError: (Object _) {
      // Allow a retry on the next request (e.g. after going back online).
      _titleLoads.remove(id);
      return null;
    });
  }

  Future<BrandArt?> loadBrand(String id) {
    final have = _brand[id];
    if (have != null) return Future.value(have);
    return _brandLoads[id] ??= repo.brandArt(id).then<BrandArt?>((a) {
      _brand[id] = a;
      return a;
    }, onError: (Object _) {
      _brandLoads.remove(id);
      return null;
    });
  }

  TapeState? stateOf(String id) {
    final t = _titles[id];
    if (t == null) return null;
    if (_statesRevision != appState.revision) {
      _states.clear();
      _statesRevision = appState.revision;
    }
    return _states[id] ??= TapeStates.stateOf(t, appState);
  }

  /// The artwork URL of [kind] for [id], when known.
  String? artUrl(String id, ArtKind kind) => switch (kind) {
        ArtKind.poster => appState.posterOverride(id) ?? _titles[id]?.poster,
        ArtKind.logo => _brand[id]?.clearLogo,
        ArtKind.banner => _brand[id]?.banner,
        ArtKind.background =>
          appState.bannerOverride(id) ?? _brand[id]?.background,
      };

  /// Shelf atlases print the spine and a front strip: poster and logo.
  static List<ArtKind> kindsFor(LabelUse use) => use == LabelUse.hero
      ? ArtKind.values
      : const [ArtKind.poster, ArtKind.logo];

  static int widthFor(ArtKind kind, LabelUse use) {
    final w = decodeWidth[kind]!;
    return use == LabelUse.hero ? w.$2 : w.$1;
  }

  String _artTag(String id, ArtKind kind, LabelUse use) {
    final url = artUrl(id, kind);
    if (url == null) return '-';
    return _imagesReady.contains('${widthFor(kind, use)}|$url') ? url : '-';
  }

  @override
  String labelKey(String titleId, {LabelUse use = LabelUse.shelf}) {
    final t = _titles[titleId];
    if (t == null) return 'pending';
    return [
      t.name,
      t.yearLine,
      stateOf(titleId)!.cacheKey,
      for (final k in kindsFor(use)) _artTag(titleId, k, use),
    ].join('|');
  }

  @override
  void prefetch(Iterable<String> titleIds) {
    for (final id in titleIds) {
      Future.wait([loadTitle(id), loadBrand(id)]).then((_) {
        for (final k in kindsFor(LabelUse.shelf)) {
          final url = artUrl(id, k);
          if (url != null) _image(url, widthFor(k, LabelUse.shelf), Duration.zero);
        }
      });
    }
  }

  @override
  Future<LabelSnapshot?> labelData(String titleId,
      {LabelUse use = LabelUse.shelf,
      Duration patience = const Duration(seconds: 3)}) async {
    final deadline = DateTime.now().add(patience);
    Duration left() {
      final d = deadline.difference(DateTime.now());
      return d.isNegative ? Duration.zero : d;
    }

    final brand = loadBrand(titleId);
    final t = _titles[titleId] ?? await _within(loadTitle(titleId), left());
    if (t == null || _disposed) return null;
    await _within(brand, left());
    final kinds = kindsFor(use);
    final urls = [for (final k in kinds) artUrl(titleId, k)];
    final images = await Future.wait([
      for (var i = 0; i < kinds.length; i++)
        urls[i] == null
            ? Future<ui.Image?>.value(null)
            : _image(urls[i]!, widthFor(kinds[i], use), left()),
    ]);
    if (_disposed) {
      for (final i in images) {
        i?.dispose();
      }
      return null;
    }
    ui.Image? img(ArtKind k) {
      final i = kinds.indexOf(k);
      return i < 0 ? null : images[i];
    }

    final state = stateOf(titleId) ?? const TapeState.notStarted();
    final data = TapeLabelData(
      titleId: titleId,
      title: t.name,
      state: state,
      year: RegExp(r'\d{4}').firstMatch(t.yearLine)?.group(0),
      isMovie: t.kind == MediaKind.movie,
      poster: img(ArtKind.poster),
      logo: img(ArtKind.logo),
      banner: img(ArtKind.banner),
      background: img(ArtKind.background),
      synopsis: t.synopsis,
      genres: t.genres,
      runtime: t.kind == MediaKind.movie
          ? RegExp(r'^\d+h \d+m').firstMatch(t.metaLine)?.group(0)
          : null,
    );
    final key = [
      t.name,
      t.yearLine,
      state.cacheKey,
      for (var i = 0; i < kinds.length; i++) images[i] == null ? '-' : urls[i],
    ].join('|');
    return LabelSnapshot(data, key);
  }

  @override
  String semanticsLabel(String titleId) {
    final t = _titles[titleId];
    if (t == null) return 'Tape';
    final st = stateOf(titleId)!;
    final kind = t.kind == MediaKind.movie ? 'movie' : 'show';
    return '${t.name}, $kind, '
        '${TapeStates.describe(st, isMovie: t.kind == MediaKind.movie)}';
  }

  /// Resolves [url] through the image cache, decoded [width] px wide.
  /// Returns a caller-owned image, or null on failure or when it takes
  /// longer than [patience]; a late arrival still marks it ready and
  /// notifies, so the labels that missed it get recomposed.
  Future<ui.Image?> _image(String url, int width, Duration patience) {
    final key = '$width|$url';
    if (_imagesFailed.contains(key)) return Future.value(null);
    final load = _resolve(url, width).then((img) {
      if (img == null) {
        _imagesFailed.add(key);
      } else {
        _imagesReady.add(key);
      }
      return img;
    });
    return _within(load, patience, onLate: (img) {
      img?.dispose();
      if (img != null) _notify();
    });
  }

  /// [f]'s value, or null once [patience] runs out ([onLate] then gets the
  /// value when it does arrive). The timer is cancelled on time, so nothing
  /// is left pending.
  static Future<T?> _within<T>(Future<T?> f, Duration patience,
      {void Function(T? value)? onLate}) {
    final done = Completer<T?>();
    final timer = patience == Duration.zero
        ? null
        : Timer(patience, () {
            if (!done.isCompleted) done.complete(null);
          });
    if (timer == null) done.complete(null);
    f.then((v) {
      timer?.cancel();
      if (done.isCompleted) {
        onLate?.call(v);
      } else {
        done.complete(v);
      }
    }, onError: (Object _) {
      timer?.cancel();
      if (!done.isCompleted) done.complete(null);
    });
    return done.future;
  }

  static Future<ui.Image?> _resolve(String url, int width) {
    final ImageProvider base =
        url.startsWith('http') ? NetworkImage(url) : AssetImage(url);
    // Decoded straight to [width] (the codec's targetWidth), never upscaled.
    final provider = ResizeImage(base, width: width, allowUpscaling: false);
    final done = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (done.isCompleted) {
        info.dispose();
      } else {
        done.complete(info.image); // ours to dispose
      }
      stream.removeListener(listener);
    }, onError: (Object _, StackTrace? __) {
      if (!done.isCompleted) done.complete(null);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return done.future;
  }

  @override
  void dispose() {
    _disposed = true;
    appState.removeListener(_onAppState);
    super.dispose();
  }
}
