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

  // Жалоба @qwinken (24.08.2026, скриншот профиля): «Загрузили нашу дату
  // знакомства, но дни вместе не обновились. Пишет 0, хотя мы вместе уже 355
  // дней. При этом время до следующей годовщины показывает корректно».
  // В профиле стояла годовщина 03.09.2025, а пара сошлась в приложении в тот же
  // день, когда он писал — расчёт брал только дату коннекта и таймера.
  group('годовщина как дата начала', () {
    final connectToday = DateTime(2026, 8, 24, 12, 0);
    final anniversary = DateTime(2025, 9, 3);
    final nowThen = DateTime(2026, 8, 24, 13, 3);

    test('пара сошлась сегодня, а годовщина год назад — считаем от годовщины', () {
      expect(
        coupleDaysTogether(
          groupStart: connectToday,
          anniversary: anniversary,
          now: nowThen,
        ),
        355,
      );
    });

    test('годовщина позже коннекта — она срок не укорачивает', () {
      expect(
        coupleStartDate(groupStart: connect, anniversary: DateTime(2026, 6, 20)),
        connect,
      );
    });

    test('годовщина раньше правленого таймера — таймер сильнее: свой срок '
        'человек уже выставил', () {
      expect(
        coupleStartDate(
          timerStart: timer,
          groupStart: connect,
          anniversary: anniversary,
        ),
        timer,
      );
    });

    test('одна годовщина без прочих дат — она и есть начало', () {
      expect(coupleStartDate(anniversary: anniversary), anniversary);
    });
  });

  // Приоритет дат. На проде 43 791 пара с системным таймером: 27 989 годовщину
  // не вводили вовсе, 3 370 ввели её и таймер не трогали (его дата равна дню
  // регистрации — случай @qwinken), 12 432 правили таймер руками, и у 1 605 из
  // них годовщина стоит РАНЬШЕ правленого таймера. Для последних «самая ранняя
  // из трёх» перебивала бы осознанный выбор человека.
  group('чья дата главнее', () {
    final connect = DateTime(2026, 8, 24, 12, 0);
    final anniversary = DateTime(2025, 9, 3);

    test('таймер правили руками — он и есть начало, даже если годовщина '
        'раньше', () {
      final edited = DateTime(2026, 1, 15);
      expect(
        coupleStartDate(
          timerStart: edited,
          groupStart: connect,
          anniversary: anniversary,
        ),
        edited,
      );
    });

    test('таймер стоит на дне регистрации — значит его не трогали, и начало '
        'берётся из годовщины', () {
      expect(
        coupleStartDate(
          timerStart: connect,
          groupStart: connect,
          anniversary: anniversary,
        ),
        anniversary,
      );
    });

    test('время суток разное, день тот же — таймер всё ещё «не тронут»', () {
      expect(
        coupleStartDate(
          timerStart: DateTime(2026, 8, 24, 20, 30),
          groupStart: connect,
          anniversary: anniversary,
        ),
        anniversary,
      );
    });

    test('годовщина позже правленого таймера — срок не укорачивает', () {
      final edited = DateTime(2024, 3, 1);
      expect(
        coupleStartDate(
          timerStart: edited,
          groupStart: connect,
          anniversary: DateTime(2025, 6, 1),
        ),
        edited,
      );
    });
  });
}
