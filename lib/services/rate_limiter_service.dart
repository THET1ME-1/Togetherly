import 'package:shared_preferences/shared_preferences.dart';

/// Thrown when an operation exceeds the per-device rate limit.
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
/// Осталось ровно одно ограничение — комментарии, 30 в час. Лимит на
/// воспоминания снят раньше, лимит на импульсы («думаю о тебе», «хочу обнять»,
/// своё пожелание) — 8 августа 2026: 20 штук за 15 минут упирались в живой
/// разговор пары, а сервер и без него держит поток (`miss-you` 600/10с).
class RateLimiterService {
  static final RateLimiterService _instance = RateLimiterService._();
  factory RateLimiterService() => _instance;
  RateLimiterService._();

  static const _keyComment = 'rl_comment_ts';
  static const _maxCommentsPerHour = 30;
  static const _hourWindow = Duration(hours: 1);

  // ── Memories ──────────────────────────────────────────────────────────────

  Future<void> checkMemory() async {}

  Future<void> recordMemory() async {}

  Future<void> checkAndRecordMemory() async {}

  // ── Comments ──────────────────────────────────────────────────────────────

  /// Throws [RateLimitException] if the comment limit is exceeded.
  Future<void> checkComment() => _check(
    key: _keyComment,
    maxCount: _maxCommentsPerHour,
    window: _hourWindow,
    itemLabel: 'комментариев',
    windowLabel: 'в час',
  );

  /// Records one successful comment write.
  Future<void> recordComment() =>
      _record(key: _keyComment, window: _hourWindow);

  /// Checks and records atomically.
  Future<void> checkAndRecordComment() async {
    await checkComment();
    await recordComment();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _check({
    required String key,
    required int maxCount,
    required Duration window,
    required String itemLabel,
    required String windowLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final cutoff = now.subtract(window);

    final recent = _readTimestamps(prefs, key)
        .where((t) => t.isAfter(cutoff))
        .toList();

    if (recent.length >= maxCount) {
      recent.sort();
      final resetAt = recent.first.add(window);
      final minutesLeft = resetAt.difference(now).inMinutes + 1;
      throw RateLimitException(
        'Не более $maxCount $itemLabel $windowLabel — попробуй через $minutesLeft мин. 🌸',
        minutesUntilReset: minutesLeft,
      );
    }
  }

  Future<void> _record({
    required String key,
    required Duration window,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final cutoff = now.subtract(window);

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
