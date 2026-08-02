import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot_sleep.dart';

/// Сон маскота.
///
/// До этого ночь была зашита намертво: с 23:00 до 07:00 у всех и без выбора.
/// Теперь у каждого персонажа своё окно, а разбор обязан выдерживать что
/// угодно с сервера — поле правит сам человек, и старые записи его не имеют.
void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 8, 1, hour, minute);

  group('Окно через полночь', () {
    const night = SleepWindow(from: 23 * 60, to: 7 * 60);

    test('Спит поздним вечером', () {
      expect(night.contains(at(23, 30)), isTrue);
    });

    test('Спит под утро', () {
      expect(night.contains(at(3)), isTrue);
    });

    test('Не спит днём', () {
      expect(night.contains(at(12)), isFalse);
    });

    test('Начало окна включено, конец нет', () {
      expect(night.contains(at(23)), isTrue);
      expect(night.contains(at(7)), isFalse);
      expect(night.contains(at(22, 59)), isFalse);
    });
  });

  group('Окно внутри суток', () {
    const nap = SleepWindow(from: 13 * 60, to: 15 * 60);

    test('Спит в свои часы', () {
      expect(nap.contains(at(14)), isTrue);
    });

    test('Не спит ни до, ни после', () {
      expect(nap.contains(at(12, 59)), isFalse);
      expect(nap.contains(at(15)), isFalse);
      expect(nap.contains(at(3)), isFalse);
    });
  });

  group('Крайние случаи', () {
    test('Выключенное окно не спит никогда', () {
      const off = SleepWindow(from: 23 * 60, to: 7 * 60, enabled: false);
      expect(off.contains(at(1)), isFalse);
      expect(off.contains(at(23, 30)), isFalse);
    });

    test('Окно нулевой длины не спит никогда', () {
      // Иначе «с 8 до 8» читалось бы как круглые сутки сна, а человек имел
      // в виду обратное — он просто сдвинул обе стрелки в одну точку.
      const zero = SleepWindow(from: 8 * 60, to: 8 * 60);
      expect(zero.contains(at(8)), isFalse);
      expect(zero.contains(at(20)), isFalse);
    });
  });

  group('Разбор того, что пришло с сервера', () {
    test('Пусто — у всех прежние 23:00–07:00', () {
      final map = MascotSleep.parse(null);
      expect(map, isEmpty);
      expect(MascotSleep.of(map, 'kuku'), SleepWindow.standard);
    });

    test('Своё окно у своего персонажа, остальным прежнее', () {
      final map = MascotSleep.parse({
        'kuku': {'from': 90, 'to': 400},
      });
      expect(MascotSleep.of(map, 'kuku'), const SleepWindow(from: 90, to: 400));
      expect(MascotSleep.of(map, 'ugolyok'), SleepWindow.standard);
    });

    test('Выключенный сон переживает разбор', () {
      final map = MascotSleep.parse({
        'migun': {'from': 60, 'to': 300, 'enabled': false},
      });
      expect(MascotSleep.of(map, 'migun').enabled, isFalse);
    });

    test('Мусор пропускается, а не роняет разбор', () {
      final map = MascotSleep.parse({
        'kuku': {'from': 90, 'to': 400},
        'битый': {'from': 'утро', 'to': 400},
        'вне суток': {'from': 5000, 'to': -3},
        'не карта': 42,
      });
      expect(map.keys, ['kuku']);
    });

    test('Строка json разбирается так же, как карта', () {
      // PocketBase отдаёт json-поле то картой, то строкой — в зависимости от
      // того, пришло оно по сети или поднялось из офлайн-кэша.
      final map = MascotSleep.parse('{"kuku":{"from":90,"to":400}}');
      expect(MascotSleep.of(map, 'kuku'), const SleepWindow(from: 90, to: 400));
    });
  });

  group('Отправка на сервер', () {
    test('Карта сворачивается в json и разбирается обратно', () {
      const one = {
        'kuku': SleepWindow(from: 90, to: 400),
        'migun': SleepWindow(from: 60, to: 300, enabled: false),
      };
      expect(MascotSleep.parse(MascotSleep.encode(one)), one);
    });

    test('Персонаж с прежним окном в поле не хранится', () {
      // Умолчание не пишем: иначе поле распухает записями, которые ничего
      // не значат, и «ничего не менял» неотличимо от «выставил ровно 23–7».
      final encoded = MascotSleep.encode({'kuku': SleepWindow.standard});
      expect(encoded, isEmpty);
    });
  });

  group('Часы и минуты для интерфейса', () {
    test('Минуты раскладываются на часы и минуты', () {
      const w = SleepWindow(from: 23 * 60 + 30, to: 7 * 60 + 15);
      expect(w.fromHour, 23);
      expect(w.fromMinute, 30);
      expect(w.toHour, 7);
      expect(w.toMinute, 15);
    });
  });
}
