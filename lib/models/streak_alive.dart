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

/// Жива ли серия маскота с последним днём [day] (07.11.2026).
///
/// Маскот не на главной — его дни не идут, но серия не обрывается, а стоит на
/// паузе, пока пара не пропускает дни: его день лежит внутри непрерывной
/// серии пары ([groupStreak] дней по [groupDay] включительно), и сама серия
/// пары жива. То же правило у сервера (`_маскот_на_паузе` в hotpath.py).
/// Раньше вернувшийся маскот начинал с единицы (канал: «с 64 на 2 сменилась»).
bool mascotStreakAlive(
  String? day, {
  String? groupDay,
  int groupStreak = 0,
  String? pendingDay,
  required DateTime now,
}) {
  if (streakAlive(day, pendingDay: pendingDay, now: now)) return true;
  return streakPausedIn(day, groupDay: groupDay, groupStreak: groupStreak, pendingDay: pendingDay, now: now);
}

/// Серия маскота стоит на паузе: его день внутри живой серии пары.
bool streakPausedIn(
  String? day, {
  String? groupDay,
  int groupStreak = 0,
  String? pendingDay,
  required DateTime now,
}) {
  if (day == null || day.isEmpty || groupDay == null || groupStreak < 1) return false;
  if (!streakAlive(groupDay, pendingDay: pendingDay, now: now)) return false;
  final a = DateTime.tryParse(groupDay), b = DateTime.tryParse(day);
  if (a == null || b == null) return false;
  final back = DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
  return back >= 0 && back <= groupStreak - 1;
}

/// День «ГГГГ-ММ-ДД» по местному календарю, как его шлёт приложение серверу.
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
