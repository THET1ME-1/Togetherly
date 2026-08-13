import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/pair_time.dart';

void main() {
  group('PairTime.zoneNow', () {
    test('пишет смещение как ±HH:MM', () {
      expect(PairTime.zoneNow(), matches(r'^[+-]\d{2}:\d{2}$'));
    });

    test('знает про получасовые пояса', () {
      expect(PairTime.zoneOf(const Duration(hours: 5, minutes: 30)), '+05:30');
      expect(PairTime.zoneOf(const Duration(hours: -3, minutes: -30)), '-03:30');
      expect(PairTime.zoneOf(Duration.zero), '+00:00');
    });
  });

  group('PairTime.write', () {
    test('отправляет момент в UTC, а не часы устройства', () {
      final moment = DateTime.fromMillisecondsSinceEpoch(1786000000000);
      final sent = PairTime.write(moment);

      expect(sent.endsWith('Z'), isTrue);
      expect(DateTime.parse(sent).millisecondsSinceEpoch,
          moment.millisecondsSinceEpoch);
    });
  });

  group('PairTime.read', () {
    test('новая запись: момент абсолютный, показываем в поясе читателя', () {
      final read = PairTime.read('2026-08-13T22:30:00.000Z', '+03:00')!;

      expect(read.isUtc, isFalse);
      expect(read.millisecondsSinceEpoch,
          DateTime.utc(2026, 8, 13, 22, 30).millisecondsSinceEpoch);
    });

    test('старая запись без пояса: часы остаются как в строке', () {
      final read = PairTime.read('2026-08-13T22:30:00.000Z', null)!;

      expect(read.isUtc, isFalse);
      expect(read.year, 2026);
      expect(read.month, 8);
      expect(read.day, 13);
      expect(read.hour, 22);
      expect(read.minute, 30);
    });

    test('пустая строка пояса читается как старая запись', () {
      final read = PairTime.read('2026-08-13T22:30:00.000Z', '')!;
      expect(read.hour, 22);
    });

    test('принимает миллисекунды числом — так пишет хук подарков', () {
      final read = PairTime.read(1786000000000, '+03:00')!;
      expect(read.millisecondsSinceEpoch, 1786000000000);
    });

    test('мусор не роняет разбор', () {
      expect(PairTime.read('позавчера', '+03:00'), isNull);
      expect(PairTime.read(null, null), isNull);
    });
  });

  group('PairTime.authorDay', () {
    test('новая запись: сутки считаются по поясу автора', () {
      // 22:30 UTC — у автора в +03:00 уже 01:30 следующего дня.
      final day = PairTime.authorDay('2026-08-13T22:30:00.000Z', '+03:00')!;

      expect(day.year, 2026);
      expect(day.month, 8);
      expect(day.day, 14);
    });

    test('автор западнее Гринвича: сутки уезжают назад', () {
      final day = PairTime.authorDay('2026-08-13T02:30:00.000Z', '-05:00')!;
      expect(day.day, 12);
    });

    test('старая запись: часы автора уже лежат в строке', () {
      final day = PairTime.authorDay('2026-08-13T22:30:00.000Z', null)!;
      expect(day.day, 13);
    });

    test('день без времени суток', () {
      final day = PairTime.authorDay('2026-08-13T22:30:00.000Z', '+03:00')!;
      expect(day.hour, 0);
      expect(day.minute, 0);
    });
  });

  group('PairTime.zoneToDuration', () {
    test('разбирает знак и минуты', () {
      expect(PairTime.zoneToDuration('+05:45'),
          const Duration(hours: 5, minutes: 45));
      expect(PairTime.zoneToDuration('-03:30'),
          const Duration(hours: -3, minutes: -30));
    });

    test('на мусоре отдаёт null, а не ноль', () {
      expect(PairTime.zoneToDuration('Москва'), isNull);
      expect(PairTime.zoneToDuration(''), isNull);
      expect(PairTime.zoneToDuration(null), isNull);
    });
  });
}
