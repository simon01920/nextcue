import 'dart:async';
import 'dart:collection';

/// Client-side request budget for one external API.
///
/// Every device shares the API's limits with every other device running the
/// app, so each one keeps itself well under them:
/// - at most [maxRequests] requests in any rolling [per] window;
/// - at most [maxConcurrent] requests in flight at once;
/// - after the server answers 429, nothing is sent until the cooldown ends
///   (see [cooldown]); callers fall back to cached data meanwhile.
///
/// A request that would have to wait longer than [maxWait] fails fast with
/// [RateLimitedException] instead of freezing the UI.
class RateLimiter {
  RateLimiter({
    required this.maxRequests,
    required this.per,
    this.maxConcurrent = 4,
    this.maxWait = const Duration(seconds: 8),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final int maxRequests;
  final Duration per;
  final int maxConcurrent;
  final Duration maxWait;
  final DateTime Function() _now;

  final Queue<DateTime> _sent = Queue();
  int _active = 0;
  DateTime? _coolUntil;
  Future<void> _gate = Future.value();

  /// True while a server-requested cooldown is in effect.
  bool get coolingDown {
    final until = _coolUntil;
    return until != null && _now().isBefore(until);
  }

  /// Stop sending for [d] (from a 429 / Retry-After). Never shortens an
  /// existing cooldown.
  void cooldown(Duration d) {
    final until = _now().add(d);
    if (_coolUntil == null || until.isAfter(_coolUntil!)) _coolUntil = until;
  }

  /// Runs [task] once the budget allows it.
  Future<T> run<T>(Future<T> Function() task) async {
    // Admission is serialized so concurrent callers can't all pass the
    // check at the same instant.
    final previous = _gate;
    final admitted = Completer<void>();
    _gate = admitted.future;
    try {
      await previous;
      await _waitForSlot();
      _active++;
      _sent.addLast(_now());
    } finally {
      admitted.complete();
    }
    try {
      return await task();
    } finally {
      _active--;
    }
  }

  Future<void> _waitForSlot() async {
    final deadline = _now().add(maxWait);
    while (true) {
      final now = _now();
      while (_sent.isNotEmpty && now.difference(_sent.first) >= per) {
        _sent.removeFirst();
      }
      Duration? wait;
      if (coolingDown) {
        wait = _coolUntil!.difference(now);
      } else if (_sent.length >= maxRequests) {
        wait = per - now.difference(_sent.first);
      } else if (_active >= maxConcurrent) {
        wait = const Duration(milliseconds: 50);
      }
      if (wait == null) return;
      if (now.add(wait).isAfter(deadline)) {
        throw RateLimitedException(wait);
      }
      await Future<void>.delayed(
        wait < const Duration(milliseconds: 10)
            ? const Duration(milliseconds: 10)
            : wait,
      );
    }
  }
}

class RateLimitedException implements Exception {
  final Duration retryIn;
  RateLimitedException(this.retryIn);
  @override
  String toString() =>
      'RateLimitedException: retry in ${retryIn.inMilliseconds} ms';
}

/// Parses a `Retry-After` (seconds) or AniList's `X-RateLimit-Reset`
/// (epoch seconds) into a cooldown, clamped to [min]..[max].
Duration retryAfter(
  Map<String, String> headers, {
  Duration fallback = const Duration(seconds: 30),
  Duration min = const Duration(seconds: 1),
  Duration max = const Duration(minutes: 2),
  DateTime? now,
}) {
  Duration d = fallback;
  final ra = int.tryParse(headers['retry-after']?.trim() ?? '');
  final reset = int.tryParse(headers['x-ratelimit-reset']?.trim() ?? '');
  if (ra != null) {
    d = Duration(seconds: ra);
  } else if (reset != null) {
    final at = DateTime.fromMillisecondsSinceEpoch(reset * 1000);
    d = at.difference(now ?? DateTime.now());
  }
  if (d < min) return min;
  if (d > max) return max;
  return d;
}
