/// Расписание показов счётчика «дней вместе».
///
/// Текст локального уведомления записывается в момент планирования и потом не
/// меняется. Одно повторяющееся уведомление («каждый день в такой-то час»)
/// поэтому всю жизнь показывает число, посчитанное когда-то давно: на iPhone
/// фоновой доставки у нас нет вовсе, пересчитать текст без открытия приложения
/// некому. Так и вышла жалоба «в приложении меняется, а в уведомлении всегда
/// 1349».
///
/// Лечится расписанием: на каждый ближайший день заводится своё уведомление со
/// своим числом. Здесь считается только расписание — платформенная часть живёт
/// в `DaysTogetherNotificationService`.
library;

/// Один показ: момент [at] и число, верное на этот момент.
class DaysTogetherTick {
  const DaysTogetherTick({required this.at, required this.days});

  /// Локальный момент показа.
  final DateTime at;

  /// Сколько дней вместе на [at].
  final int days;
}

/// Ближайшие [count] показов, начиная с первого [hour]:[minute] после [from].
///
/// Число считается той же формулой, что и в приложении
/// (`coupleDaysTogether`): разница в полных сутках от [start], минимум 0.
List<DaysTogetherTick> daysTogetherTicks({
  required DateTime start,
  required DateTime from,
  required int count,
  int hour = 9,
  int minute = 0,
}) {
  if (count <= 0) return const [];

  var first = DateTime(from.year, from.month, from.day, hour, minute);
  if (!first.isAfter(from)) {
    first = DateTime(from.year, from.month, from.day + 1, hour, minute);
  }

  return List.generate(count, (i) {
    // Через компоненты, а не `add(Duration(days: 1))`: при переводе часов
    // сутки не равны 24 часам, и время показа уползло бы.
    final at = DateTime(first.year, first.month, first.day + i, hour, minute);
    final days = at.difference(start).inDays;
    return DaysTogetherTick(at: at, days: days < 0 ? 0 : days);
  });
}
