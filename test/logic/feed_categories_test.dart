// Тег «Капсулы» в ленте воспоминаний.
//
// Жалоба 31.08.2026: человек получил уведомление об открытии капсулы, зашёл и
// не нашёл её — искать было негде. Теги ленты знали только тип записи, а
// капсула типом не является: это флаг поверх текста или фото, и в списке она
// пряталась среди «Заметок» и «Моментов».
//
// Значит тег фильтрует по флагу, а не по типу, и появляется в ряду только у
// тех пар, у кого капсулы есть.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/models/feed_category.dart';
import 'package:love_app/models/memory.dart';

Memory _memory({
  required MemoryType type,
  bool sealed = false,
  DateTime? openAt,
}) =>
    Memory(
      id: 'm1',
      groupId: 'g1',
      authorUid: 'u1',
      authorName: 'Миша',
      type: type,
      createdAt: DateTime(2026, 3, 1),
      sealed: sealed,
      openAt: openAt,
    );

void main() {
  final capsule = _memory(
    type: MemoryType.text,
    sealed: true,
    openAt: DateTime(2026, 8, 31),
  );
  final note = _memory(type: MemoryType.text);
  final photo = _memory(type: MemoryType.photo);

  FeedCategory byKey(String key) =>
      kFeedCategories.firstWhere((c) => c.key == key);

  group('Тег «Капсулы»', () {
    test('Капсула проходит фильтр капсул', () {
      expect(byKey('capsules').matches(capsule), isTrue);
    });

    test('Обычная заметка в капсулы не попадает', () {
      expect(byKey('capsules').matches(note), isFalse);
      expect(byKey('capsules').matches(photo), isFalse);
    });

    test('Запечатанное фото — тоже капсула', () {
      final sealedPhoto = _memory(
        type: MemoryType.photo,
        sealed: true,
        openAt: DateTime(2027, 1, 1),
      );
      expect(byKey('capsules').matches(sealedPhoto), isTrue);
    });

    test('Капсула остаётся и в теге своего типа', () {
      expect(byKey('notes').matches(capsule), isTrue);
    });
  });

  group('Какие теги показывать', () {
    test('Без капсул тега капсул в ряду нет', () {
      final keys = presentFeedCategories([note, photo]).map((c) => c.key);
      expect(keys, isNot(contains('capsules')));
      expect(keys, containsAll(['notes', 'moments']));
    });

    test('С капсулой тег появляется', () {
      final keys = presentFeedCategories([note, capsule]).map((c) => c.key);
      expect(keys, contains('capsules'));
    });

    test('Капсулы идут первыми: за ними приходят из уведомления', () {
      final keys =
          presentFeedCategories([photo, note, capsule]).map((c) => c.key);
      expect(keys.first, 'capsules');
    });

    test('Пустая лента — пустой ряд', () {
      expect(presentFeedCategories(const []), isEmpty);
    });
  });

  group('Переводы', () {
    test('У каждого тега есть подпись на всех семи языках', () {
      const codes = ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de'];
      for (final c in kFeedCategories) {
        for (final code in codes) {
          final label = trDict(c.dictKey, code);
          expect(label, isNot(c.dictKey),
              reason: 'нет перевода ${c.dictKey} на $code');
          expect(label.trim(), isNotEmpty);
        }
      }
    });
  });
}
