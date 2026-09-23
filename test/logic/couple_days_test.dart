import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/couple_days.dart';

void main() {
  // Данные из реального инцидента: пара сошлась в приложении 31 мая, а срок
  // отношений ведёт с 12 мая (дата системного таймера). Профиль показывал 54
  // дня вместо 73 — считал от коннекта (и полными сутками, см. ниже).
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
    // Главный экран (`TimerItem.daysElapsed`) считает клетки календаря: с 12
    // мая по 25 июля — 74 дня, и в восемь утра, и в полночь.
    test('срок совпадает с главным экраном, а не с датой коннекта', () {
      expect(
        coupleDaysTogether(timerStart: timer, groupStart: connect, now: now),
        74,
      );
    });

    test('без таймера считает от коннекта', () {
      expect(coupleDaysTogether(groupStart: connect, now: now), 55);
    });

    // Жалоба 18.09.2026, скриншот с iPhone в 01:31: вместе с 05.07.2025, таймер
    // пары показывает 440, а виджет «Дней вместе» и профиль — 439. Счёт шёл
    // полными сутками от часа начала, и до этого часа каждый день выходил на
    // единицу меньше календарного.
    test('ночью до часа начала день не теряется', () {
      expect(
        coupleDaysTogether(
          timerStart: DateTime(2025, 7, 5, 15, 0),
          now: DateTime(2026, 9, 18, 1, 31),
        ),
        440,
      );
    });

    // В поясе с летним временем сутки перевода длятся 23 часа, и разница
    // полуночей через конец марта на час короче целого числа суток.
    test('переход на летнее время не отнимает день', () {
      expect(
        calendarDaysBetween(DateTime(2026, 3, 20), DateTime(2026, 4, 1, 12)),
        12,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 10, 20), DateTime(2026, 11, 1)),
        12,
      );
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

  group('предложить счёт от годовщины', () {
    // Живой случай: годовщину ввели с годом 2003, согласились вести счёт от
    // неё, и таймер ушёл на 17.07.2003. Потом год исправили на 2026, а
    // предложения не было: переносили только назад, и счётчик застрял на
    // 8467 днях.
    final wrong = DateTime(2003, 7, 17);
    final fixed = DateTime(2026, 7, 17);
    final today = DateTime(2026, 9, 23, 12);

    test('годовщина раньше таймера — предлагаем, как и раньше', () {
      expect(
        shouldOfferCounterFromAnniversary(
          anniversary: DateTime(2025, 1, 5),
          timerStart: DateTime(2026, 3, 1),
          now: today,
        ),
        isTrue,
      );
    });

    test('годовщина на том же дне, что таймер, — переносить нечего', () {
      expect(
        shouldOfferCounterFromAnniversary(
          anniversary: DateTime(2026, 3, 1),
          previousAnniversary: DateTime(2020, 3, 1),
          timerStart: DateTime(2026, 3, 1, 18, 30),
          now: today,
        ),
        isFalse,
      );
    });

    test('таймер стоит на прежней годовщине — исправление вперёд тоже '
        'предлагаем', () {
      expect(
        shouldOfferCounterFromAnniversary(
          anniversary: fixed,
          previousAnniversary: wrong,
          timerStart: wrong,
          now: today,
        ),
        isTrue,
      );
    });

    test('час в таймере другой, день тот же — всё равно это прежняя '
        'годовщина', () {
      expect(
        shouldOfferCounterFromAnniversary(
          anniversary: fixed,
          previousAnniversary: DateTime(2003, 7, 17, 0, 0),
          timerStart: DateTime(2003, 7, 17, 21, 15),
          now: today,
        ),
        isTrue,
      );
    });

    test('таймер правили отдельно — вперёд его не двигаем', () {
      expect(
        shouldOfferCounterFromAnniversary(
          anniversary: fixed,
          previousAnniversary: wrong,
          timerStart: DateTime(2010, 2, 14),
          now: today,
        ),
        isFalse,
      );
    });

    test('прежней годовщины не было — вперёд не предлагаем', () {
      expect(
        shouldOfferCounterFromAnniversary(
          anniversary: fixed,
          timerStart: wrong,
          now: today,
        ),
        isFalse,
      );
    });

    test('годовщина в будущем — счёт от неё не ведём', () {
      expect(
        shouldOfferCounterFromAnniversary(
          anniversary: DateTime(2026, 11, 2),
          previousAnniversary: wrong,
          timerStart: wrong,
          now: today,
        ),
        isFalse,
      );
    });
  });
}
