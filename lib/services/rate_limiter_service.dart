import 'package:shared_preferences/shared_preferences.dart';

/// Thrown when an operation exceeds the per-device hourly rate limit.
class RateLimitException implements Exception {
  final String message;
  final int minutesUntilReset;

  const RateLimitException(this.message, {this.minutesUntilReset = 1});

  @override
  String toString() => message;
}

/// Client-side rate limiter backed by SharedPreferences.
/// Prevents excessive Firestore writes without blocking legitimate use.
///
/// Limits:
///   - Memories : 10 per hour
///   - Comments : 30 per hour
class RateLimiterService {
  static final RateLimiterService _instance = RateLimiterService._();
  factory RateLimiterService() => _instance;
  RateLimiterService._();

  static const _keyMemory = 'rl_memory_ts';
  static const _keyComment = 'rl_comment_ts';
  static const _maxMemoriesPerHour = 10;
  static const _maxCommentsPerHour = 30;
  static const _window = Duration(hours: 1);

  // ── Memories ──────────────────────────────────────────────────────────────

  /// Throws [RateLimitException] if the memory limit is exceeded.
  /// Does NOT record — call [recordMemory] after the write succeeds.
  Future<void> checkMemory() => _check(
    key: _keyMemory,
    maxCount: _maxMemoriesPerHour,
    itemLabel: 'воспоминаний',
  );

  /// Records one successful memory write.
  Future<void> recordMemory() => _record(key: _keyMemory);

  /// Checks and records atomically — use when there is no early check opportunity.
  Future<void> checkAndRecordMemory() async {
    await checkMemory();
    await recordMemory();
  }

  // ── Comments ──────────────────────────────────────────────────────────────

  /// Throws [RateLimitException] if the comment limit is exceeded.
  Future<void> checkComment() => _check(
    key: _keyComment,
    maxCount: _maxCommentsPerHour,
    itemLabel: 'комментариев',
  );

  /// Records one successful comment write.
  Future<void> recordComment() => _record(key: _keyComment);

  /// Checks and records atomically.
  Future<void> checkAndRecordComment() async {
    await checkComment();
    await recordComment();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _check({
    required String key,
    required int maxCount,
    required String itemLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final cutoff = now.subtract(_window);

    final recent = _readTimestamps(prefs, key)
        .where((t) => t.isAfter(cutoff))
        .toList();

    if (recent.length >= maxCount) {
      recent.sort();
      final resetAt = recent.first.add(_window);
      final minutesLeft = resetAt.difference(now).inMinutes + 1;
      throw RateLimitException(
        'Не более $maxCount $itemLabel в час — попробуй через $minutesLeft мин. 🌸',
        minutesUntilReset: minutesLeft,
      );
    }
  }

  Future<void> _record({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final cutoff = now.subtract(_window);

    final kept = _readTimestamps(prefs, key)
        .where((t) => t.isAfter(cutoff))
        .toList()
      ..add(now);

    await prefs.setStringList(
      key,
      kept.map((t) => t.toIso8601String()).toList(),
    );
  }

  List<DateTime> _readTimestamps(SharedPreferences prefs, String key) {
    return (prefs.getStringList(key) ?? [])
        .map((s) => DateTime.tryParse(s))
        .whereType<DateTime>()
        .toList();
  }
}
