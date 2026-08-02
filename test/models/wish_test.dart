import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/wish.dart';
import 'package:love_app/models/wish_category.dart';

/// Общий список желаний пары.
///
/// Разделение на «мечтаем» и «сбылось» считается по данным записи, а не по
/// вкладке экрана: отметку ставит любой из двоих, и второму телефону она
/// приезжает дельтой Centrifugo — вкладка при этом может быть открыта другая.
void main() {
  Wish wish(
    String id, {
    bool done = false,
    DateTime? doneAt,
    DateTime? createdAt,
    String categoryId = 'other',
    String symbol = '',
  }) =>
      Wish(
        id: id,
        title: 'Желание $id',
        categoryId: categoryId,
        symbol: symbol,
        authorUid: 'u1',
        done: done,
        doneAt: doneAt,
        createdAt: createdAt ?? DateTime(2026, 1, 1),
      );

  group('Категории', () {
    test('У каждой встроенной свой значок из подшитого шрифта', () {
      final names = kBuiltinWishKinds.map((k) => k.symbol).toList();
      expect(names.toSet().length, names.length);
      expect(names, everyElement(isNotEmpty));
    });

    test('Незнакомый ключ встроенной категорией не притворяется', () {
      expect(builtinWishKind('concert'), isNull);
      expect(builtinWishKind(null), isNull);
      expect(builtinWishKind('movie')?.symbol, 'movie');
    });

    test('Своя категория находится среди заведённых парой', () {
      const mine = WishKind(
          id: 'abc123', symbol: 'sports_tennis', titleRu: 'Спорт', custom: true);
      final kind = resolveWishKind(
          categoryId: 'abc123', symbol: 'sports_tennis', custom: [mine]);

      expect(kind.id, 'abc123');
      expect(kind.title(true), 'Спорт');
      expect(kind.custom, isTrue);
    });

    test('Удалённая категория оставляет желанию его значок', () {
      final kind = resolveWishKind(
          categoryId: 'снесли', symbol: 'sports_tennis', custom: const []);

      expect(kind.symbol, 'sports_tennis');
      expect(kind.title(true), 'Своё');
    });

    test('Ни категории, ни значка — падаем на «Своё»', () {
      final kind =
          resolveWishKind(categoryId: 'снесли', symbol: '', custom: const []);
      expect(kind.symbol, 'star');
    });

    test('Своя категория подписана одним названием на оба языка', () {
      const mine =
          WishKind(id: 'x', symbol: 'star', titleRu: 'Баня', custom: true);
      expect(mine.title(true), 'Баня');
      expect(mine.title(false), 'Баня');
    });
  });

  group('Значок желания', () {
    test('Записи первых сборок берут значок встроенной категории', () {
      expect(wish('w1', categoryId: 'movie').iconName, 'movie');
    });

    test('Сохранённый значок сильнее категории', () {
      expect(wish('w1', categoryId: 'movie', symbol: 'ramen').iconName, 'ramen');
    });
  });

  group('Хранение', () {
    test('Запись переживает круг через карту без потерь', () {
      final source = Wish(
        id: 'w1',
        title: '«Дюна: Часть третья»',
        note: 'только IMAX',
        categoryId: 'movie',
        symbol: 'movie',
        authorUid: 'u1',
        done: true,
        doneAt: DateTime(2026, 3, 12),
        doneBy: 'u2',
        doneNote: 'Плакали оба',
        createdAt: DateTime(2026, 2, 1),
      );

      final back = Wish.fromMap(source.toMap(groupId: 'g1'));

      expect(back.id, source.id);
      expect(back.title, source.title);
      expect(back.note, source.note);
      expect(back.categoryId, 'movie');
      expect(back.symbol, 'movie');
      expect(back.done, isTrue);
      expect(back.doneAt, source.doneAt);
      expect(back.doneBy, 'u2');
      expect(back.doneNote, 'Плакали оба');
    });

    test('Своя категория хранится своим id', () {
      final map = wish('w1', categoryId: 'pb0987654321', symbol: 'pets')
          .toMap(groupId: 'g1');
      expect(map['category'], 'pb0987654321');
      expect(map['symbol'], 'pets');
    });

    test('group_id уходит в карту — по нему работает правило доступа', () {
      expect(wish('w1').toMap(groupId: 'g1')['group_id'], 'g1');
    });

    test('Пустая заметка в карту не пишется', () {
      final map = wish('w1').toMap(groupId: 'g1');
      expect(map.containsKey('note'), isFalse);
      expect(map.containsKey('done_note'), isFalse);
    });
  });

  group('Разделение списка', () {
    final items = [
      wish('a', createdAt: DateTime(2026, 1, 1)),
      wish('b', createdAt: DateTime(2026, 3, 1)),
      wish('c', done: true, doneAt: DateTime(2026, 2, 1)),
      wish('d', done: true, doneAt: DateTime(2026, 4, 1)),
    ];

    test('Мечтаем — только неотмеченные, свежие сверху', () {
      expect(Wish.dreaming(items).map((w) => w.id), ['b', 'a']);
    });

    test('Сбылось — только отмеченные, последнее сверху', () {
      expect(Wish.fulfilled(items).map((w) => w.id), ['d', 'c']);
    });

    test('Отметка без даты не роняет сортировку', () {
      final list = [
        wish('x', done: true),
        wish('y', done: true, doneAt: DateTime(2026, 5, 1)),
      ];
      expect(Wish.fulfilled(list).map((w) => w.id), ['y', 'x']);
    });
  });

  group('Отметка', () {
    test('«Сбылось» проставляет дату и того, кто отметил', () {
      final marked = wish('w1').markDone(by: 'u2', at: DateTime(2026, 5, 9));

      expect(marked.done, isTrue);
      expect(marked.doneBy, 'u2');
      expect(marked.doneAt, DateTime(2026, 5, 9));
    });

    test('Отмена возвращает желание в «мечтаем» и стирает след отметки', () {
      final back = wish('w1', done: true, doneAt: DateTime(2026, 5, 9))
          .markDone(by: 'u2', at: DateTime(2026, 5, 9))
          .undone();

      expect(back.done, isFalse);
      expect(back.doneAt, isNull);
      expect(back.doneBy, isEmpty);
      expect(back.doneNote, isEmpty);
    });
  });
}
