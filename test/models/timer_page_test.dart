import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/timer_page.dart';

void main() {
  group('timerPageFor', () {
    test('пока человек не листал, карусель стоит на основном таймере', () {
      // Список таймеров приезжает позже первого кадра: на старте он пуст, и
      // страница вставала на нулевую. Отсюда жалоба «после каждого запуска
      // нужно мотать в сторону» (скриншот 13 августа 2026).
      expect(
        timerPageFor(
          ids: const ['sys', 'together', 'wedding'],
          defaultId: 'wedding',
          current: 0,
          userSwiped: false,
        ),
        2,
      );
    });

    test('свайп человека сильнее основного таймера', () {
      expect(
        timerPageFor(
          ids: const ['sys', 'together', 'wedding'],
          defaultId: 'wedding',
          current: 1,
          userSwiped: true,
        ),
        1,
      );
    });

    test('основной таймер удалили — остаёмся где стояли', () {
      expect(
        timerPageFor(
          ids: const ['sys', 'together'],
          defaultId: 'wedding',
          current: 1,
          userSwiped: false,
        ),
        1,
      );
    });

    test('страница за концом списка прижимается к последней', () {
      expect(
        timerPageFor(
          ids: const ['sys', 'together'],
          defaultId: null,
          current: 5,
          userSwiped: true,
        ),
        1,
      );
    });

    test('пустой список не даёт отрицательной страницы', () {
      expect(
        timerPageFor(
          ids: const [],
          defaultId: 'sys',
          current: 3,
          userSwiped: false,
        ),
        0,
      );
    });
  });
}
