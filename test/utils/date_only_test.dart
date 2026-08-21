// Календарная дата не должна гулять между поясами.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/date_only.dart';

void main() {
  group('как дата уходит на сервер', () {
    test('только год, месяц и день — ни часа, ни пояса', () {
      expect(DateOnly.store(DateTime(2001, 7, 18)), '2001-07-18');
      expect(DateOnly.store(DateTime(2001, 7, 18, 23, 59)), '2001-07-18');
      expect(DateOnly.store(DateTime(2003, 1, 17, 0, 1)), '2003-01-17');
    });

    test('однозначные месяц и день дополняются нулём', () {
      expect(DateOnly.store(DateTime(2005, 3, 4)), '2005-03-04');
    });

    test('пустая дата остаётся пустой', () {
      expect(DateOnly.store(null), isNull);
    });
  });

  group('как дата читается обратно', () {
    test('чистая дата читается день в день', () {
      final d = DateOnly.parse('2001-07-18')!;
      expect([d.year, d.month, d.day], [2001, 7, 18]);
    });

    test('старый момент разворачивается в местный день', () {
      // Именно этот вид лежит на проде: час взят из момента сохранения.
      final d = DateOnly.parse('2004-10-25T20:54:00.000Z')!;
      final local = DateTime.utc(2004, 10, 25, 20, 54).toLocal();
      expect([d.year, d.month, d.day], [local.year, local.month, local.day]);
    });

    test('запись из Firestore тоже читается', () {
      final d = DateOnly.parse({'_seconds': 1098737640, '_nanoseconds': 0})!;
      final local = DateTime.fromMillisecondsSinceEpoch(1098737640 * 1000);
      expect([d.year, d.month, d.day], [local.year, local.month, local.day]);
    });

    test('мусор и пустота не роняют экран', () {
      expect(DateOnly.parse(null), isNull);
      expect(DateOnly.parse(''), isNull);
      expect(DateOnly.parse('не дата'), isNull);
      expect(DateOnly.parse({'что-то': 1}), isNull);
    });

    test('прочитанная дата не несёт времени', () {
      final d = DateOnly.parse('2001-07-18T23:30:00.000Z')!;
      expect([d.hour, d.minute, d.second], [0, 0, 0]);
    });
  });

  group('круг «сохранил — прочитал» не сдвигает день', () {
    test('дата рождения переживает запись и чтение', () {
      for (final day in [
        DateTime(2001, 7, 18),
        DateTime(2003, 1, 17),
        DateTime(2000, 2, 29),
        DateTime(1999, 12, 31),
        DateTime(2005, 1, 1),
      ]) {
        final back = DateOnly.parse(DateOnly.store(day))!;
        expect([back.year, back.month, back.day], [day.year, day.month, day.day],
            reason: 'день $day не должен уезжать');
      }
    });

    test('поздний вечер не перескакивает на завтра', () {
      final late = DateTime(2001, 7, 18, 23, 59, 59);
      final back = DateOnly.parse(DateOnly.store(late))!;
      expect([back.year, back.month, back.day], [2001, 7, 18]);
    });
  });

  test('сравнение по дню не смотрит на время', () {
    expect(
      DateOnly.sameDay(DateTime(2001, 7, 18), DateTime(2001, 7, 18, 20, 54)),
      isTrue,
    );
    expect(
      DateOnly.sameDay(DateTime(2001, 7, 18), DateTime(2001, 7, 19)),
      isFalse,
    );
    expect(DateOnly.sameDay(null, DateTime(2001, 7, 18)), isFalse);
  });

  group('день рождения не зависит от пояса читающего', () {
    // Жалоба 21.08.2026 со скриншотами обоих экранов: она поставила
    // 12.04.2001, партнёр видит 13.04.2001. Момент времени разворачивался в
    // МЕСТНОЕ время того, кто смотрит, и у пары из разных стран дата уезжала
    // на сутки.
    test('поздний вечер по UTC остаётся тем же числом', () {
      final d = DateOnly.parse('2001-04-12T23:30:00.000Z');
      expect(d!.day, 12);
      expect(d.month, 4);
      expect(d.year, 2001);
    });

    test('ранние часы по UTC тоже остаются своим числом', () {
      final d = DateOnly.parse('2003-02-20T00:15:00.000Z');
      expect(d!.day, 20);
      expect(d.month, 2);
    });

    test('строка без пояса читается так же, как с ним', () {
      expect(DateOnly.parse('2001-04-12T18:30:00.000'),
          DateOnly.parse('2001-04-12T18:30:00.000Z'));
    });

    test('чистая дата по-прежнему читается как есть', () {
      final d = DateOnly.parse('2001-04-12');
      expect(d, DateTime(2001, 4, 12));
    });
  });
}
