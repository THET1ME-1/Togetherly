import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot.dart';
import 'package:love_app/models/streak_restore.dart';
import 'package:love_app/utils/calendar_day.dart';
import 'package:pocketbase/pocketbase.dart';

/// TOG-26, отзыв в App Store 17.10.2026: «Мы заходим оба, отправляем друг
/// другу подарки, а на следующий день маскот обнуляется».
///
/// Сервер засчитывает день датой того, кто отметился первым, а второму даёт
/// прийти и на следующий день по своим часам (`_общий_день` в hotpath). У
/// пары, где второй заходит после полуночи, последний засчитанный день весь
/// следующий день лежит «позавчера», а вчерашнее ожидание партнёра ещё
/// засчитается. Телефон считал серию живой только при «сегодня» или «вчера»
/// и рисовал ноль, маскота малышом и предлагал «вернуть серию». На живой
/// базе 25.10.2026 в 15:06 так выглядели 1265 пар из 9898 с серией от двух
/// дней.
void main() {
  String day(int shift) {
    final d = calendarDay(DateTime.now(), shift);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  GroupMascotState state({required String d, String? pending}) => GroupMascotState(
        activeMascotId: 'm',
        streakLastOpenedDate: d,
        streakPendingDate: pending,
        mascotStreaks: {'m': {'s': 12, 'd': d}},
      );

  test('позавчера, но вчера кто-то из пары отметился и ждёт второго — серия жива', () {
    final s = state(d: day(-2), pending: day(-1));
    expect(s.activeStreak, 12, reason: 'живую серию телефон рисует нулём');
    expect(s.moodState, MascotMoodState.happy);
  });

  test('позавчера и вчерашнего ожидания нет — серия порвана', () {
    expect(state(d: day(-2)).activeStreak, 0);
    // Ждут сегодняшнего: вчерашний день пропущен, его уже не засчитать.
    expect(state(d: day(-2), pending: day(0)).activeStreak, 0);
  });

  test('три дня назад не спасает и ожидание: день между ними пропущен', () {
    expect(state(d: day(-3), pending: day(-1)).activeStreak, 0);
  });

  test('сегодня и вчера — серия жива, как и раньше', () {
    expect(state(d: day(0)).activeStreak, 12);
    expect(state(d: day(-1)).activeStreak, 12);
  });

  test('живую серию вернуть за ролик не предлагают', () {
    final entry = {'s': 12, 'd': day(-2)};
    expect(streakRestoreOffer(entry, DateTime.now(), pendingDay: day(-1)), isNull,
        reason: 'пара ждёт второго, а телефон пугает сгоревшей серией');
    expect(streakRestoreOffer(entry, DateTime.now(), pendingDay: day(0))?.days, 12);
    expect(streakRestoreOffer(entry, DateTime.now())?.days, 12);
  });

  test('ожидание читается из записи пары', () {
    final s = GroupMascotState.fromPb(RecordModel({
      'id': 'g',
      'streak_pending_date': '2026-10-24',
      'streak_last_opened_date': '2026-10-23',
    }));
    expect(s.streakPendingDate, '2026-10-24');
    expect(GroupMascotState.fromPb(RecordModel({'id': 'g', 'streak_pending_date': ''}))
        .streakPendingDate, isNull);
  });
}
