import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-show tracking status, mirroring the source app's overflow-menu states.
enum TrackStatus { watching, planToWatch, stopped, completed }

TrackStatus? trackStatusFrom(String? s) {
  for (final v in TrackStatus.values) {
    if (v.name == s) return v;
  }
  return null;
}

/// Account-scoped interactive state, persisted to shared_preferences under a
/// per-uid namespace so every registered account keeps its own watch-state,
/// statuses, ratings, reactions and artwork choices.
class AppState extends ChangeNotifier {
  SharedPreferences? _prefs;
  String _uid = 'anon';

  ThemeMode _themeMode = ThemeMode.dark;
  final Set<String> _watchedEpisodes = {};
  final Set<String> _favorites = {};
  final Map<String, int> _episodeRatings = {};
  final Map<String, String> _reactions = {};
  final Map<String, String> _devices = {}; // episodeId -> device label
  final Map<String, String> _favChars = {}; // episodeId -> character name
  final Map<String, int> _lastWatchedAt = {}; // titleId -> epoch ms
  final Map<String, int> _watchedAt = {}; // episodeId -> epoch ms
  final Map<String, TrackStatus> _statuses = {}; // titleId -> status
  final Map<String, String> _posterOverride = {}; // titleId -> url
  final Map<String, String> _bannerOverride = {};

  String get uid => _uid;
  ThemeMode get themeMode => _themeMode;

  /// Monotonic change counter so list screens can cheaply memoize futures.
  int revision = 0;

  String _k(String key) => 'bingely.$_uid.$key';

  /// Bind this state to an account and load its persisted data.
  Future<void> bind(String uid, {bool seedDemo = false}) async {
    _uid = uid;
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;

    _watchedEpisodes
      ..clear()
      ..addAll(p.getStringList(_k('watched')) ?? const []);
    _favorites
      ..clear()
      ..addAll(p.getStringList(_k('favorites')) ?? const []);
    _episodeRatings
      ..clear()
      ..addAll((jsonDecode(p.getString(_k('ratings')) ?? '{}')
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)));
    _reactions
      ..clear()
      ..addAll((jsonDecode(p.getString(_k('reactions')) ?? '{}')
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String)));
    _devices
      ..clear()
      ..addAll((jsonDecode(p.getString(_k('devices')) ?? '{}')
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String)));
    _favChars
      ..clear()
      ..addAll((jsonDecode(p.getString(_k('favChars')) ?? '{}')
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String)));
    _lastWatchedAt
      ..clear()
      ..addAll((jsonDecode(p.getString(_k('lastWatched')) ?? '{}')
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)));
    _watchedAt
      ..clear()
      ..addAll((jsonDecode(p.getString(_k('watchedAt')) ?? '{}')
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)));
    // Resume the monotonic stamp above anything already persisted, so
    // history ordering survives a restart.
    _lastStampMs = _watchedAt.values.fold<int>(0, (a, b) => a > b ? a : b);
    _statuses.clear();
    (jsonDecode(p.getString(_k('statuses')) ?? '{}') as Map<String, dynamic>)
        .forEach((k, v) {
      final st = trackStatusFrom(v as String?);
      if (st != null) _statuses[k] = st;
    });
    _posterOverride
      ..clear()
      ..addAll((jsonDecode(p.getString(_k('posters')) ?? '{}')
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String)));
    _bannerOverride
      ..clear()
      ..addAll((jsonDecode(p.getString(_k('banners')) ?? '{}')
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String)));
    _themeMode = ThemeMode.values[
        p.getInt(_k('themeMode')) ?? ThemeMode.dark.index];

    // Seed the claimed profile's account once: Your Lie in April tracked
    // as watching with S1E1–E11 watched (matching the recon snapshot).
    if (seedDemo && !(p.getBool(_k('seeded')) ?? false)) {
      _statuses['series-279830'] = TrackStatus.watching;
      for (var e = 1; e <= 11; e++) {
        _watchedEpisodes.add('series-279830:1:$e');
      }
      await p.setBool(_k('seeded'), true);
      await _save();
    }
    notifyListeners();
  }

  /// One-shot per-account flag: true only the first time [key] is claimed.
  Future<bool> claimOnce(String key) async {
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    if (p.getBool(_k(key)) ?? false) return false;
    await p.setBool(_k(key), true);
    return true;
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setStringList(_k('watched'), _watchedEpisodes.toList());
    await p.setStringList(_k('favorites'), _favorites.toList());
    await p.setString(_k('ratings'), jsonEncode(_episodeRatings));
    await p.setString(_k('reactions'), jsonEncode(_reactions));
    await p.setString(_k('devices'), jsonEncode(_devices));
    await p.setString(_k('favChars'), jsonEncode(_favChars));
    await p.setString(_k('lastWatched'), jsonEncode(_lastWatchedAt));
    await p.setString(_k('watchedAt'), jsonEncode(_watchedAt));
    await p.setString(_k('statuses'),
        jsonEncode(_statuses.map((k, v) => MapEntry(k, v.name))));
    await p.setString(_k('posters'), jsonEncode(_posterOverride));
    await p.setString(_k('banners'), jsonEncode(_bannerOverride));
    await p.setInt(_k('themeMode'), _themeMode.index);
  }

  void _mutate(void Function() fn) {
    fn();
    revision++;
    notifyListeners();
    _save();
  }

  void setThemeMode(ThemeMode m) => _mutate(() => _themeMode = m);

  // Watched episodes -----------------------------------------------------
  bool isWatched(String episodeId) => _watchedEpisodes.contains(episodeId);

  /// Strictly-increasing watch stamps.
  ///
  /// Several episodes can be marked inside the same millisecond (tapping
  /// fast, or "mark whole season"). Equal stamps would make the history
  /// order arbitrary — and history exists so the user can undo *the thing
  /// they just pressed* — so each stamp is forced past the previous one.
  int _lastStampMs = 0;

  void _stampLastWatched(String episodeId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stamp = now > _lastStampMs ? now : _lastStampMs + 1;
    _lastStampMs = stamp;
    _lastWatchedAt[episodeId.split(':').first] = stamp;
    _watchedAt[episodeId] = stamp;
  }

  void toggleWatched(String episodeId) => _mutate(() {
        if (!_watchedEpisodes.add(episodeId)) {
          _watchedEpisodes.remove(episodeId);
          _watchedAt.remove(episodeId);
        } else {
          _stampLastWatched(episodeId);
        }
      });
  void setWatched(String episodeId, bool watched) => _mutate(() {
        if (watched) {
          _watchedEpisodes.add(episodeId);
          _stampLastWatched(episodeId);
        } else {
          _watchedEpisodes.remove(episodeId);
          _watchedAt.remove(episodeId);
        }
      });

  /// Marks every supplied episode watched (or unwatched) in one write —
  /// used by the season-level check and the "mark all" actions.
  void setManyWatched(Iterable<String> episodeIds, bool watched) => _mutate(() {
        for (final id in episodeIds) {
          if (watched) {
            _watchedEpisodes.add(id);
            _stampLastWatched(id);
          } else {
            _watchedEpisodes.remove(id);
            _watchedAt.remove(id);
          }
        }
      });

  /// When a specific episode was marked watched (null if never / legacy).
  DateTime? watchedAt(String episodeId) {
    final ms = _watchedAt[episodeId];
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Watch history, newest first. Episodes watched before timestamps were
  /// recorded (legacy data) sort last but are still listed, so nothing the
  /// user has marked is invisible to the history sheet.
  List<String> get watchHistory {
    final ids = _watchedEpisodes.toList();
    ids.sort((a, b) => (_watchedAt[b] ?? 0).compareTo(_watchedAt[a] ?? 0));
    return ids;
  }

  /// When the user last marked any episode of [titleId] watched.
  DateTime? lastWatchedAt(String titleId) {
    final ms = _lastWatchedAt[titleId];
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
  int watchedCountFor(String titleId) =>
      _watchedEpisodes.where((e) => e.startsWith('$titleId:')).length;
  int get watchedEpisodeTotal => _watchedEpisodes.length;

  // Favorites — the VHS shelf. Capped per tier. -----------------------------
  static const int favoriteLimitFree = 15;
  static const int favoriteLimitPremium = 30; // no premium accounts yet

  bool isFavorite(String titleId) => _favorites.contains(titleId);

  /// Returns false when the shelf is full (free limit) and nothing changed.
  bool toggleFavorite(String titleId) {
    if (_favorites.contains(titleId)) {
      _mutate(() => _favorites.remove(titleId));
      return true;
    }
    if (_favorites.length >= favoriteLimitFree) return false;
    _mutate(() => _favorites.add(titleId));
    return true;
  }

  List<String> get favoriteIds => _favorites.toList();

  // Ratings / reactions ---------------------------------------------------
  int? ratingOf(String episodeId) => _episodeRatings[episodeId];
  void rate(String episodeId, int stars) =>
      _mutate(() => _episodeRatings[episodeId] = stars);
  String? reactionOf(String episodeId) => _reactions[episodeId];
  void react(String episodeId, String emotion) => _mutate(() {
        _reactions[episodeId] == emotion
            ? _reactions.remove(episodeId)
            : _reactions[episodeId] = emotion;
      });

  // Watched-on device / favorite character (per episode) -------------------
  String? deviceOf(String episodeId) => _devices[episodeId];
  void setDevice(String episodeId, String device) => _mutate(() {
        _devices[episodeId] == device
            ? _devices.remove(episodeId)
            : _devices[episodeId] = device;
      });
  String? favoriteCharOf(String episodeId) => _favChars[episodeId];
  void setFavoriteChar(String episodeId, String name) => _mutate(() {
        _favChars[episodeId] == name
            ? _favChars.remove(episodeId)
            : _favChars[episodeId] = name;
      });

  // Track statuses ---------------------------------------------------------
  TrackStatus? statusOf(String titleId) => _statuses[titleId];
  void setStatus(String titleId, TrackStatus? status) => _mutate(() {
        if (status == null) {
          _statuses.remove(titleId);
        } else {
          _statuses[titleId] = status;
        }
      });
  List<String> idsWithStatus(TrackStatus status) => _statuses.entries
      .where((e) => e.value == status)
      .map((e) => e.key)
      .toList();
  List<String> get trackedIds => _statuses.keys.toList();

  // Artwork overrides ------------------------------------------------------
  String? posterOverride(String titleId) => _posterOverride[titleId];
  String? bannerOverride(String titleId) => _bannerOverride[titleId];
  void setPoster(String titleId, String url) =>
      _mutate(() => _posterOverride[titleId] = url);
  void setBanner(String titleId, String url) =>
      _mutate(() => _bannerOverride[titleId] = url);
}
