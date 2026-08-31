// Открывшаяся капсула поднимается в ленте.
//
// Жалоба 31.08.2026: «После нажатия на уведомление об открытии капсулы
// открывается окно с предложением купить подписку, а после капсулу нигде не
// найти и не открыть». Капсулу пишут за месяцы до срока, и в ленте она стоит
// по дате создания — то есть глубоко внизу. В день открытия человек получает
// уведомление, заходит и не находит ничего: сверху лежат yesterdayшние записи.
//
// Значит день открытия и есть событие капсулы: с этого дня она сортируется по
// нему, а не по дате, когда её запечатали.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_sort.dart';

void main() {
  final longAgo = DateTime(2026, 3, 1);
  final yesterday = DateTime(2026, 8, 30);
  final today = DateTime(2026, 8, 31);

  group('Капсула в ленте', () {
    test('Открывшаяся сегодня капсула идёт выше вчерашней записи', () {
      final order = compareMemories(
        MemorySort.eventDate,
        aEvent: longAgo, aOpenAt: today,     // капсула, запечатана в марте
        bEvent: yesterday,                        // обычное воспоминание
      );
      expect(order, lessThan(0), reason: 'капсула должна быть первой');
    });

    test('Ещё запечатанная капсула наверх не лезет', () {
      final order = compareMemories(
        MemorySort.eventDate,
        aEvent: longAgo, aOpenAt: DateTime(2027, 1, 1),   // откроется через год
        bEvent: yesterday,
      );
      expect(order, greaterThan(0), reason: 'до срока капсула на своём месте');
    });

    test('То же правило работает и при сортировке по дате добавления', () {
      final order = compareMemories(
        MemorySort.addedAt,
        aEvent: longAgo, aAdded: longAgo, aOpenAt: today,
        bEvent: yesterday, bAdded: yesterday,
      );
      expect(order, lessThan(0));
    });

    test('Без капсулы сортировка прежняя', () {
      expect(
        compareMemories(MemorySort.eventDate, aEvent: yesterday, bEvent: today),
        greaterThan(0),
      );
      expect(
        compareMemories(MemorySort.eventDate, aEvent: today, bEvent: yesterday),
        lessThan(0),
      );
    });
  });
}
