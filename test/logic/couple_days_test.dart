import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/couple_days.dart';

void main() {
  // Данные из реального инцидента: пара сошлась в приложении 31 мая, а срок
  // отношений ведёт с 12 мая (дата системного таймера). Профиль показывал 54
  // дня вместо 73 — считал от коннекта.
  final connect = DateTime(2026, 5, 31, 20, 40);
  final timer = DateTime(2026, 5, 12, 23, 40);
  final now = DateTime(2026, 7, 25, 8, 0);

  group('coupleStartDate', () {
    test('берёт более раннюю из двух дат', () {
      expect(
        coupleStartDate(timerStart: timer, groupStart: connect),
        timer,
      );
    });

    test('таймер позже коннекта — считаем от коннекта', () {
      final lateTimer = DateTime(2026, 6, 10);
      expect(
        coupleStartDate(timerStart: lateTimer, groupStart: connect),
        connect,
      );
    });

    test('одна дата — она и есть начало', () {
      expect(coupleStartDate(groupStart: connect), connect);
      expect(coupleStartDate(timerStart: timer), timer);
    });

    test('дат нет — null', () {
      expect(coupleStartDate(), isNull);
    });
  });

  group('coupleDaysTogether', () {
    test('срок совпадает с главным экраном, а не с датой коннекта', () {
      expect(
        coupleDaysTogether(timerStart: timer, groupStart: connect, now: now),
        73,
      );
    });

    test('без таймера считает от коннекта', () {
      expect(coupleDaysTogether(groupStart: connect, now: now), 54);
    });

    test('дата в будущем даёт 0', () {
      expect(
        coupleDaysTogether(timerStart: DateTime(2026, 8, 1), now: now),
        0,
      );
    });

    test('дат нет — null', () {
      expect(coupleDaysTogether(now: now), isNull);
    });
  });
}
