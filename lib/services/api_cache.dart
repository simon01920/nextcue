import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two-tier response cache for external API calls (TVDB / AniList), with
/// in-flight coalescing. Tier 1 is an in-memory map; tier 2 persists raw JSON
/// bodies to shared_preferences so restarts don't re-spend API quota.
///
/// Design notes (strategy PDFs → "cache API calls, save rate limits"):
/// - Keys are full request identities (URI or query+variables hash).
/// - Entries carry a storedAt timestamp; TTL is supplied per call so each
///   endpoint class can age differently.
/// - Web localStorage is ~5 MB shared with app state, so persistence is
///   size-aware: per-entry cap, total budget, LRU eviction via a small index,
///   and quota-exception fallback that degrades to memory-only. A cache write
///   must never break a fetch.
class ApiCache {
  ApiCache(
    this._prefs, {
    this.totalBudgetBytes = 2560000,
    this.maxEntryBytes = 153600,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _loadIndex();
  }

  /// Bump v1 → v2 to invalidate every persisted entry on schema changes.
  static const String keyPrefix = 'nc.cache.v1.';
  static const String _indexKey = '${keyPrefix}index';

  final SharedPreferences _prefs;
  final int totalBudgetBytes;
  final int maxEntryBytes;
  final DateTime Function() _clock;

  final Map<String, _MemEntry> _mem = {};
  final Map<String, Future<String>> _inFlight = {};

  /// hash → {t: storedAt ms, u: lastUsed ms, s: size bytes}
  final Map<String, Map<String, int>> _index = {};

  void _loadIndex() {
    try {
      final raw = _prefs.getString(_indexKey);
      if (raw == null) return;
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
        _index[k] = (v as Map<String, dynamic>)
            .map((k2, v2) => MapEntry(k2, v2 as int));
      });
    } catch (_) {
      _index.clear();
    }
  }

  static String hashKey(String key) =>
      sha1.convert(utf8.encode(key)).toString().substring(0, 20);

  String _entryKey(String hash) => '${keyPrefix}e.$hash';

  /// Single entry point: memory hit → persisted hit (TTL-checked) →
  /// coalesced network fetch. Only successful fetch results are stored.
  Future<String> through({
    required String key,
    required Duration ttl,
    required Future<String> Function() fetch,
  }) {
    final now = _clock();

    // Tier 1: memory.
    final mem = _mem[key];
    if (mem != null && now.difference(mem.storedAt) < ttl) {
      _touch(hashKey(key));
      return Future.value(mem.body);
    }

    // Tier 2: persisted.
    final hash = hashKey(key);
    try {
      final raw = _prefs.getString(_entryKey(hash));
      if (raw != null) {
        final obj = jsonDecode(raw) as Map<String, dynamic>;
        final storedAt =
            DateTime.fromMillisecondsSinceEpoch(obj['t'] as int? ?? 0);
        if (now.difference(storedAt) < ttl) {
          final body = obj['b'] as String;
          _mem[key] = _MemEntry(body, storedAt);
          _touch(hash);
          return Future.value(body);
        }
      }
    } catch (_) {
      // Corrupt entry — treat as miss.
    }

    // Coalesce concurrent identical fetches.
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = fetch().then((body) {
      _put(key, body);
      return body;
    }).whenComplete(() {
      // NOTE: block body is load-bearing. `whenComplete` awaits a Future
      // returned by its callback, and `Map.remove` returns the removed
      // value — which here is this very future. An arrow body would make
      // the future wait on itself and hang forever.
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  void _touch(String hash) {
    final e = _index[hash];
    if (e != null) e['u'] = _clock().millisecondsSinceEpoch;
    // Index flushed on next put/evict — avoids write churn on read hits.
  }

  void _put(String key, String body) {
    final now = _clock();
    _mem[key] = _MemEntry(body, now);
    final size = body.length;
    if (size > maxEntryBytes) return; // memory-only

    final hash = hashKey(key);
    final entry = jsonEncode({'t': now.millisecondsSinceEpoch, 'b': body});
    try {
      _prefs.setString(_entryKey(hash), entry);
      _index[hash] = {
        't': now.millisecondsSinceEpoch,
        'u': now.millisecondsSinceEpoch,
        's': size,
      };
      _evictToBudget();
      _flushIndex();
    } catch (_) {
      // Quota or backend failure: evict aggressively and retry once.
      try {
        _evictBytes(totalBudgetBytes ~/ 2);
        _prefs.setString(_entryKey(hash), entry);
        _index[hash] = {
          't': now.millisecondsSinceEpoch,
          'u': now.millisecondsSinceEpoch,
          's': size,
        };
        _flushIndex();
      } catch (_) {
        // Degrade to memory-only. Never let caching break a fetch.
      }
    }
  }

  int get persistedBytes =>
      _index.values.fold(0, (sum, e) => sum + (e['s'] ?? 0));

  void _evictToBudget() {
    if (persistedBytes <= totalBudgetBytes) return;
    _evictBytes(persistedBytes - totalBudgetBytes);
  }

  void _evictBytes(int bytesToFree) {
    var freed = 0;
    final byLastUsed = _index.entries.toList()
      ..sort((a, b) => (a.value['u'] ?? 0).compareTo(b.value['u'] ?? 0));
    for (final e in byLastUsed) {
      if (freed >= bytesToFree) break;
      freed += e.value['s'] ?? 0;
      _prefs.remove(_entryKey(e.key));
      _index.remove(e.key);
    }
  }

  void _flushIndex() {
    try {
      _prefs.setString(_indexKey, jsonEncode(_index));
    } catch (_) {}
  }

  Future<void> clear() async {
    _mem.clear();
    for (final hash in _index.keys.toList()) {
      await _prefs.remove(_entryKey(hash));
    }
    _index.clear();
    await _prefs.remove(_indexKey);
    // Also sweep any orphaned entries from older sessions.
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith(keyPrefix)) await _prefs.remove(k);
    }
  }
}

class _MemEntry {
  final String body;
  final DateTime storedAt;
  _MemEntry(this.body, this.storedAt);
}
