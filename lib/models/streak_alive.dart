import '../utils/calendar_day.dart';

/// Жива ли серия, последний общий день которой [day] (TOG-26).
///
/// Сервер засчитывает день датой того, кто отметился первым, а второму даёт
/// прийти и на следующий день по своим часам (`_общий_день` в
/// pocketbase/hotpath/hotpath.py). Поэтому серия жива не только когда
/// последний общий день сегодня или вчера, но и когда он позавчера, а вчера
/// кто-то из пары уже отметился и ждёт второго ([pendingDay]): приход второго
/// засчитает вчерашний день, и серия продолжится.
///
/// Без этого у пары, где второй заходит после полуночи, телефон весь
/// следующий день рисовал серию нулём, маскота малышом и предлагал вернуть
/// серию за ролик (отзыв в App Store 17.10.2026: «на следующий день маскот
/// обнуляется»; на живой базе 25.10.2026 так выглядела каждая восьмая пара с
/// серией).
bool streakAlive(String? day, {String? pendingDay, required DateTime now}) {
  if (day == null || day.isEmpty) return false;
  final yesterday = dayKey(calendarDay(now, -1));
  if (day == dayKey(now) || day == yesterday) return true;
  return day == dayKey(calendarDay(now, -2)) && pendingDay == yesterday;
}

/// День «ГГГГ-ММ-ДД» по местному календарю, как его шлёт приложение серверу.
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
