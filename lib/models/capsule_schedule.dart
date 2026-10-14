/// Сроки капсулы времени: быстрые кнопки экрана создания и отсчёт дней.
///
/// Капсула открывается в девять утра выбранного дня: в это время приходит
/// уведомление и автору, и партнёру.
library;

/// Быстрый срок: «Месяц», «Полгода», «Год».
enum CapsulePreset { month, halfYear, year }

/// Час открытия капсулы.
const int kCapsuleOpenHour = 9;

int _monthsOf(CapsulePreset p) => switch (p) {
      CapsulePreset.month => 1,
      CapsulePreset.halfYear => 6,
      CapsulePreset.year => 12,
    };

/// Дата открытия быстрого срока: тот же день через месяц, полгода или год, в
/// девять утра.
///
/// Числа, которого нет в нужном месяце, прижимаются к его последнему дню:
/// `DateTime` превращал 31 февраля в 3 марта, и капсула «через полгода» от
/// 31 августа открывалась на три дня позже обещанного.
DateTime capsulePresetDate(DateTime now, CapsulePreset preset) {
  final first = DateTime(now.year, now.month + _monthsOf(preset));
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  final day = now.day > lastDay ? lastDay : now.day;
  return DateTime(first.year, first.month, day, kCapsuleOpenHour);
}

/// Какой быстрый срок совпадает с [openAt]. null — дату выбрали барабанами.
CapsulePreset? capsulePresetOf(DateTime openAt, DateTime now) {
  for (final p in CapsulePreset.values) {
    final d = capsulePresetDate(now, p);
    if (d.year == openAt.year && d.month == openAt.month && d.day == openAt.day) {
      return p;
    }
  }
  return null;
}

/// Какая доля срока прошла: от запечатывания [sealedAt] до открытия [openAt].
/// Полоса прогресса пина в ленте. Открытие не позже запечатывания считается
/// вышедшим сроком.
double capsuleElapsedShare(DateTime sealedAt, DateTime openAt, DateTime now) {
  final total = openAt.difference(sealedAt).inMilliseconds;
  if (total <= 0) return 1;
  final passed = now.difference(sealedAt).inMilliseconds;
  return (passed / total).clamp(0.0, 1.0).toDouble();
}

/// Сколько дней до открытия по календарю. Завтра — один день, даже если до
/// девяти утра меньше суток: `inDays` в этом случае давал ноль, и экран
/// показывал «0 дней» у капсулы, которая ещё закрыта.
int capsuleDaysLeft(DateTime openAt, DateTime now) {
  final open = DateTime.utc(openAt.year, openAt.month, openAt.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = open.difference(today).inDays;
  return days < 0 ? 0 : days;
}
