import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot.dart';
import 'package:love_app/models/streak_alive.dart';
import 'package:love_app/models/streak_restore.dart';
import 'package:love_app/utils/calendar_day.dart';

// Смена маскота ставит его серию на паузу (канал, 07.11.2026: «с 64 на 2
// сменилась», «почему нигде не было указано, что у каждого своя серия»).
// Сервер продолжает серию маскота, если его последний день лежит внутри
// непрерывной серии пары (`_маскот_на_паузе` в hotpath.py). Телефон обязан
// считать так же: показать серию на паузе, а не ноль, и не предлагать вернуть
// её за ролик.
void main() {
  final now = DateTime(2026, 11, 7, 12);
  String day(int back) => dayKey(calendarDay(now, -back));

  GroupMascotState state({required int pair, required String last, required Map<String, dynamic> streaks, String active = 'kuku'}) =>
      GroupMascotState(activeMascotId: active, streakDays: pair, streakLastOpenedDate: last, mascotStreaks: streaks);

  test('маскот на паузе: пара заходила каждый день', () {
    // Ту считался 6 дней назад, потом 5 дней с Куку, серия пары 26.
    final s = state(pair: 26, last: day(1), streaks: {
      'tu': {'s': 20, 'd': day(6)},
      'kuku': {'s': 5, 'd': day(1)},
    });
    expect(s.streakForAt('tu', now), 20);
    expect(s.streakForAt('kuku', now), 5);
    expect(s.streakPaused('tu', now), isTrue);
    expect(s.streakPaused('kuku', now), isFalse, reason: 'Куку на главной, его серия идёт');
  });

  test('пара пропустила день — пауза не спасает', () {
    final s = state(pair: 2, last: day(1), streaks: {
      'tu': {'s': 20, 'd': day(6)},
    });
    expect(s.streakForAt('tu', now), 0);
    expect(s.streakPaused('tu', now), isFalse);
  });

  test('серия пары оборвана — у маскота на паузе тоже ноль', () {
    final s = state(pair: 26, last: day(3), streaks: {
      'tu': {'s': 20, 'd': day(8)},
    });
    expect(s.streakForAt('tu', now), 0);
  });

  test('правило живой серии маскота', () {
    expect(mascotStreakAlive(day(6), groupDay: day(1), groupStreak: 26, now: now), isTrue);
    expect(mascotStreakAlive(day(6), groupDay: day(1), groupStreak: 5, now: now), isFalse);
    expect(mascotStreakAlive(day(1), groupDay: day(1), groupStreak: 1, now: now), isTrue);
    expect(mascotStreakAlive('', groupDay: day(1), groupStreak: 26, now: now), isFalse);
  });

  test('за ролик не предлагаем вернуть серию на паузе', () {
    final entry = <String, dynamic>{'s': 20, 'd': day(3)};
    expect(streakRestoreOffer(entry, now), isNotNull, reason: 'без серии пары это обрыв');
    expect(streakRestoreOffer(entry, now, groupDay: day(1), groupStreak: 10), isNull);
  });
}
