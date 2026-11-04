import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloud_sync.dart';

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
  AppState({this.cloud, this.cloudDebounce = const Duration(seconds: 3)});

  /// Remote copy of the account's state (Firestore once Firebase is
  /// configured). Null keeps everything on-device, exactly as before.
  final CloudSync? cloud;

  /// How long edits gather before one cloud write: rapid swiping becomes a
  /// single document write, which keeps well inside the free daily quota.
  final Duration cloudDebounce;

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
    // Writes still queued for the previous account must land under *its*
    // namespace before the uid changes.
    await _flush();
    await _flushCloud();
    _uid = uid;
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    _loadFromPrefs(p);

    // Seed the claimed profile's account once: Your Lie in April tracked
    // as watching with S1E1–E11 watched (matching the recon snapshot).
    if (seedDemo && !(p.getBool(_k('seeded')) ?? false)) {
      _statuses['series-279830'] = TrackStatus.watching;
      for (var e = 1; e <= 11; e++) {
        _addWatched('series-279830:1:$e');
      }
      await p.setBool(_k('seeded'), true);
      _dirty.addAll(const ['statuses', 'watched']);
      _cloudDirty.addAll(const ['statuses', 'watched']);
      await _flush();
    }
    notifyListeners();

    // Local data paints first; the cloud copy is merged when it arrives so
    // startup never waits on the network.
    if (cloud != null) unawaited(_pullCloud(uid));
  }

  void _loadFromPrefs(SharedPreferences p) {
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
    _watchedPerTitle.clear();
    for (final id in _watchedEpisodes) {
      _bumpTitleCount(id, 1);
    }
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
    final mode = p.getInt(_k('themeMode')) ?? ThemeMode.dark.index;
    _themeMode = ThemeMode.values[mode.clamp(0, ThemeMode.values.length - 1)];
  }

  // Cloud sync ---------------------------------------------------------------

  /// Every key that is persisted (locally and in the cloud).
  static const List<String> persistedKeys = [
    'watched',
    'favorites',
    'ratings',
    'reactions',
    'devices',
    'favChars',
    'lastWatched',
    'watchedAt',
    'statuses',
    'posters',
    'banners',
    'themeMode',
  ];

  final Set<String> _cloudDirty = {};
  Timer? _cloudTimer;

  /// The persisted value for [key], in the shape stored on disk.
  Object _rawValue(String key) => switch (key) {
        'watched' => _watchedEpisodes.toList(),
        'favorites' => _favorites.toList(),
        'themeMode' => _themeMode.index,
        _ => _encode(key),
      };

  Future<void> _pullCloud(String uid) async {
    final remote = await cloud!.load(uid);
    final p = _prefs;
    if (p == null || uid != _uid) return; // account changed meanwhile
    if (remote == null) {
      // First sign-in for this account (or offline): upload what this
      // device has so the next device starts from it.
      _cloudDirty.addAll(persistedKeys);
      _scheduleCloud();
      return;
    }
    // Remote wins, except for keys edited on this device since binding;
    // those are still queued for upload and stay as they are.
    var changed = false;
    for (final key in persistedKeys) {
      if (_cloudDirty.contains(key) || _dirty.contains(key)) continue;
      final v = remote[key];
      try {
        if (v is List) {
          await p.setStringList(_k(key), v.map((e) => '$e').toList());
        } else if (v is int) {
          await p.setInt(_k(key), v);
        } else if (v is String) {
          jsonDecode(v); // reject a corrupt field rather than load it
          await p.setString(_k(key), v);
        } else {
          continue;
        }
        changed = true;
      } catch (_) {
        // Skip a malformed field; the local value stays.
      }
    }
    if (!changed || uid != _uid) return;
    _loadFromPrefs(p);
    revision++;
    notifyListeners();
  }

  void _scheduleCloud() {
    if (cloud == null) return;
    _cloudTimer?.cancel();
    _cloudTimer = Timer(cloudDebounce, () => unawaited(_flushCloud()));
  }

  Future<void> _flushCloud() async {
    _cloudTimer?.cancel();
    _cloudTimer = null;
    final c = cloud;
    if (c == null || _cloudDirty.isEmpty || _uid == 'anon') return;
    final payload = {for (final k in _cloudDirty) k: _rawValue(k)};
    _cloudDirty.clear();
    try {
      await c.save(_uid, payload);
    } catch (_) {
      // Firestore queues offline writes itself; anything else is retried
      // with the next edit.
      _cloudDirty.addAll(payload.keys);
    }
  }

  /// Sends queued edits now (e.g. before sign-out or when the app pauses).
  Future<void> syncNow() async {
    await _flush();
    await _flushCloud();
  }

  @override
  void dispose() {
    _cloudTimer?.cancel();
    super.dispose();
  }

  /// One-shot per-account flag: true only the first time [key] is claimed.
  Future<bool> claimOnce(String key) async {
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    if (p.getBool(_k(key)) ?? false) return false;
    await p.setBool(_k(key), true);
    return true;
  }

  /// Persisted keys changed since the last write. Mutations only mark what
  /// they touched, and writes are coalesced to one per frame/microtask, so
  /// "mark whole season" or rapid swiping re-encodes one map once instead of
  /// re-serializing every map on every tap.
  final Set<String> _dirty = {};
  Future<void>? _pendingSave;

  String _encode(String key) => switch (key) {
        'ratings' => jsonEncode(_episodeRatings),
        'reactions' => jsonEncode(_reactions),
        'devices' => jsonEncode(_devices),
        'favChars' => jsonEncode(_favChars),
        'lastWatched' => jsonEncode(_lastWatchedAt),
        'watchedAt' => jsonEncode(_watchedAt),
        'statuses' => jsonEncode(_statuses.map((k, v) => MapEntry(k, v.name))),
        'posters' => jsonEncode(_posterOverride),
        'banners' => jsonEncode(_bannerOverride),
        _ => throw ArgumentError(key),
      };

  Future<void> _flush() async {
    final p = _prefs;
    if (p == null || _dirty.isEmpty) return;
    final keys = _dirty.toList();
    _dirty.clear();
    for (final key in keys) {
      switch (key) {
        case 'watched':
          await p.setStringList(_k(key), _watchedEpisodes.toList());
        case 'favorites':
          await p.setStringList(_k(key), _favorites.toList());
        case 'themeMode':
          await p.setInt(_k(key), _themeMode.index);
        default:
          await p.setString(_k(key), _encode(key));
      }
    }
  }

  void _scheduleSave() {
    _pendingSave ??= Future<void>.microtask(() async {
      _pendingSave = null;
      await _flush();
    });
  }

  /// Applies [fn], marks [keys] for persistence and notifies once.
  void _mutate(List<String> keys, void Function() fn) {
    fn();
    _dirty.addAll(keys);
    _cloudDirty.addAll(keys);
    revision++;
    notifyListeners();
    _scheduleSave();
    _scheduleCloud();
  }

  // Per-title watched counts, kept in step with _watchedEpisodes so list
  // screens don't scan every watched episode for every row they paint.
  final Map<String, int> _watchedPerTitle = {};

  static String _titleOf(String episodeId) {
    final i = episodeId.indexOf(':');
    return i < 0 ? episodeId : episodeId.substring(0, i);
  }

  void _bumpTitleCount(String episodeId, int delta) {
    final t = _titleOf(episodeId);
    final n = (_watchedPerTitle[t] ?? 0) + delta;
    if (n <= 0) {
      _watchedPerTitle.remove(t);
    } else {
      _watchedPerTitle[t] = n;
    }
  }

  void _addWatched(String episodeId) {
    if (_watchedEpisodes.add(episodeId)) _bumpTitleCount(episodeId, 1);
  }

  void _removeWatched(String episodeId) {
    if (_watchedEpisodes.remove(episodeId)) _bumpTitleCount(episodeId, -1);
    _watchedAt.remove(episodeId);
  }

  static const _watchKeys = ['watched', 'watchedAt', 'lastWatched'];

  void setThemeMode(ThemeMode m) =>
      _mutate(const ['themeMode'], () => _themeMode = m);

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
    _lastWatchedAt[_titleOf(episodeId)] = stamp;
    _watchedAt[episodeId] = stamp;
  }

  void toggleWatched(String episodeId) =>
      setWatched(episodeId, !_watchedEpisodes.contains(episodeId));
  void setWatched(String episodeId, bool watched) => _mutate(_watchKeys, () {
        if (watched) {
          _addWatched(episodeId);
          _stampLastWatched(episodeId);
        } else {
          _removeWatched(episodeId);
        }
      });

  /// Marks every supplied episode watched (or unwatched) in one write —
  /// used by the season-level check and the "mark all" actions.
  void setManyWatched(Iterable<String> episodeIds, bool watched) =>
      _mutate(_watchKeys, () {
        for (final id in episodeIds) {
          if (watched) {
            _addWatched(id);
            _stampLastWatched(id);
          } else {
            _removeWatched(id);
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

  int watchedCountFor(String titleId) => _watchedPerTitle[titleId] ?? 0;
  int get watchedEpisodeTotal => _watchedEpisodes.length;

  // Favorites — the VHS shelf. Capped per tier. -----------------------------
  static const int favoriteLimitFree = 15;
  static const int favoriteLimitPremium = 30; // no premium accounts yet

  bool isFavorite(String titleId) => _favorites.contains(titleId);

  /// Returns false when the shelf is full (free limit) and nothing changed.
  bool toggleFavorite(String titleId) {
    if (_favorites.contains(titleId)) {
      _mutate(const ['favorites'], () => _favorites.remove(titleId));
      return true;
    }
    if (_favorites.length >= favoriteLimitFree) return false;
    _mutate(const ['favorites'], () => _favorites.add(titleId));
    return true;
  }

  List<String> get favoriteIds => _favorites.toList();

  // Ratings / reactions ---------------------------------------------------
  int? ratingOf(String episodeId) => _episodeRatings[episodeId];
  void rate(String episodeId, int stars) =>
      _mutate(const ['ratings'], () => _episodeRatings[episodeId] = stars);
  String? reactionOf(String episodeId) => _reactions[episodeId];
  void react(String episodeId, String emotion) =>
      _mutate(const ['reactions'], () {
        _reactions[episodeId] == emotion
            ? _reactions.remove(episodeId)
            : _reactions[episodeId] = emotion;
      });

  // Watched-on device / favorite character (per episode) -------------------
  String? deviceOf(String episodeId) => _devices[episodeId];
  void setDevice(String episodeId, String device) =>
      _mutate(const ['devices'], () {
        _devices[episodeId] == device
            ? _devices.remove(episodeId)
            : _devices[episodeId] = device;
      });
  String? favoriteCharOf(String episodeId) => _favChars[episodeId];
  void setFavoriteChar(String episodeId, String name) =>
      _mutate(const ['favChars'], () {
        _favChars[episodeId] == name
            ? _favChars.remove(episodeId)
            : _favChars[episodeId] = name;
      });

  // Track statuses ---------------------------------------------------------
  TrackStatus? statusOf(String titleId) => _statuses[titleId];
  void setStatus(String titleId, TrackStatus? status) =>
      _mutate(const ['statuses'], () {
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
      _mutate(const ['posters'], () => _posterOverride[titleId] = url);
  void setBanner(String titleId, String url) =>
      _mutate(const ['banners'], () => _bannerOverride[titleId] = url);
}
