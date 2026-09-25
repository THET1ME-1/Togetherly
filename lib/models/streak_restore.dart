/// Возврат сгоревшей серии за рекламный ролик.
///
/// Просьба из чата 25.09.2026: «А есть восстановление серии как в ТикТоке?».
/// Возвращать можно за каждый обрыв, сколько угодно раз, но не позже трёх
/// дней после него. Правило повторяет серверное (`_возврат_серии` в
/// pocketbase/hotpath/hotpath.py): кнопка появляется только там, где сервер
/// согласится вернуть серию.
library;

/// Сколько дней после обрыва серию ещё можно вернуть.
const int kStreakRestoreWindowDays = 3;

/// Что вернёт ролик: [days] — серия после возврата, [key] — отметка обрыва,
/// чтобы предложение не всплывало повторно по тому же обрыву.
class StreakRestoreOffer {
  final int days;
  final String key;
  const StreakRestoreOffer({required this.days, required this.key});
}

/// Предложение вернуть серию по записи маскота из `mascot_streaks`
/// (`{s, d, lost?, lost_d?}`) или `null`, если возвращать нечего.
///
/// Обрыв бывает двух видов. Пара уже вернулась, и зачёт дня сбросил серию
/// в единицу — прежнее число сервер положил в `lost`. Пара ещё не вернулась —
/// последний общий день позавчера или раньше, на экране 0, а в записи
/// прежнее число.
StreakRestoreOffer? streakRestoreOffer(Map<String, dynamic>? entry, DateTime now) {
  if (entry == null) return null;
  final s = _int(entry['s']);
  final lost = _int(entry['lost']);
  final lostDay = _day(entry['lost_d']);
  final today = DateTime(now.year, now.month, now.day);

  if (lost >= 2 && lostDay != null) {
    final passed = today.difference(lostDay).inDays;
    if (passed >= 0 && passed <= kStreakRestoreWindowDays) {
      return StreakRestoreOffer(days: s + lost, key: 'lost:${entry['lost_d']}');
    }
  }

  final day = _day(entry['d']);
  if (s >= 2 && day != null) {
    final gap = today.difference(day).inDays;
    if (gap >= 2 && gap <= kStreakRestoreWindowDays + 1) {
      return StreakRestoreOffer(days: s, key: 'gap:${entry['d']}');
    }
  }
  return null;
}

int _int(Object? v) => v is num ? v.toInt() : 0;

DateTime? _day(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final d = DateTime.tryParse(v);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}
