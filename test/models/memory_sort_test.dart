import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_sort.dart';

class _Item {
  const _Item(this.name, this.eventDate, this.addedAt);
  final String name;
  final DateTime eventDate;
  final DateTime? addedAt;
}

void main() {
  final oldEventAddedToday = _Item(
    'свадьба 2019',
    DateTime(2019, 6, 1),
    DateTime(2026, 8, 13),
  );
  final freshEventAddedLong = _Item(
    'вчерашний ужин',
    DateTime(2026, 8, 12),
    DateTime(2026, 8, 12),
  );
  final noAddedAt = _Item('старая запись', DateTime(2026, 1, 5), null);

  List<_Item> sorted(MemorySort order, List<_Item> items) {
    final copy = [...items];
    copy.sort((a, b) => compareMemories(
          order,
          aEvent: a.eventDate,
          bEvent: b.eventDate,
          aAdded: a.addedAt,
          bAdded: b.addedAt,
        ));
    return copy;
  }

  group('compareMemories', () {
    test('по дате события сверху то, что произошло позже', () {
      final list = sorted(MemorySort.eventDate,
          [oldEventAddedToday, freshEventAddedLong]);
      expect(list.first.name, 'вчерашний ужин');
    });

    test('по добавлению сверху то, что занесли последним', () {
      // Просьба тестера: свадьбу 2019 года добавили сегодня, и в ленте по
      // дате события она уезжает в самый низ.
      final list = sorted(MemorySort.addedAt,
          [freshEventAddedLong, oldEventAddedToday]);
      expect(list.first.name, 'свадьба 2019');
    });

    test('без даты добавления берётся дата события', () {
      // У записей, созданных до появления поля, даты добавления нет — иначе
      // они свалились бы в конец списка все разом.
      final list = sorted(MemorySort.addedAt, [noAddedAt, freshEventAddedLong]);
      expect(list.first.name, 'вчерашний ужин');
      expect(list.last.name, 'старая запись');
    });

    test('одинаковые даты не роняют порядок', () {
      final a = _Item('a', DateTime(2026, 8, 1), DateTime(2026, 8, 1));
      final b = _Item('b', DateTime(2026, 8, 1), DateTime(2026, 8, 1));
      expect(sorted(MemorySort.eventDate, [a, b]).length, 2);
      expect(sorted(MemorySort.addedAt, [a, b]).length, 2);
    });
  });

  group('MemorySort', () {
    test('порядок читается из строки и обратно', () {
      for (final order in MemorySort.values) {
        expect(memorySortFromName(order.name), order);
      }
    });

    test('незнакомое значение даёт сортировку по дате события', () {
      expect(memorySortFromName('чепуха'), MemorySort.eventDate);
      expect(memorySortFromName(null), MemorySort.eventDate);
    });
  });
}
