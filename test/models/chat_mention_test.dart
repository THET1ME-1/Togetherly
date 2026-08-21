import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_mention.dart';
import 'package:love_app/models/memory.dart';

/// Прикрепление воспоминания в чат: человек жмёт «собачку», видит список
/// своих записей и выбирает одну. На айфоне список не появлялся вовсе — и
/// кнопка выглядела сломанной, хотя ломалась загрузка записей.
Memory _m(String id, String title, [MemoryType type = MemoryType.photo]) =>
    Memory(
      id: id,
      groupId: 'g',
      authorUid: 'u',
      authorName: 'Я',
      type: type,
      title: title,
      createdAt: DateTime(2026, 8, 1),
    );

void main() {
  group('отбор подсказок', () {
    final pins = [
      _m('1', 'Оазис'),
      _m('2', 'Пейзажик'),
      _m('3', 'Мда'),
    ];

    test('пустой запрос показывает всё, что есть', () {
      expect(mentionMatches(pins, '').length, 3);
    });

    test('ищем по названию, регистр не важен', () {
      expect(mentionMatches(pins, 'оаз').single.id, '1');
      expect(mentionMatches(pins, 'ОАЗ').single.id, '1');
    });

    test('длинный список режется, чтобы не закрыть собой чат', () {
      final many = [for (var i = 0; i < 40; i++) _m('$i', 'Запись $i')];
      expect(mentionMatches(many, '').length, lessThanOrEqualTo(6));
    });
  });

  group('подпись записи', () {
    test('нет названия — берём подпись', () {
      final m = Memory(
        id: 'x',
        groupId: 'g',
        authorUid: 'u',
        authorName: 'Я',
        type: MemoryType.photo,
        caption: 'Вечер на набережной',
        createdAt: DateTime(2026, 8, 1),
      );
      expect(mentionLabel(m), 'Вечер на набережной');
    });

    test('нет ни названия, ни подписи — берём место', () {
      final m = Memory(
        id: 'x',
        groupId: 'g',
        authorUid: 'u',
        authorName: 'Я',
        type: MemoryType.location,
        locationName: '6, Xeropotamos',
        createdAt: DateTime(2026, 8, 1),
      );
      expect(mentionLabel(m), '6, Xeropotamos');
    });
  });

  group('когда панель на экране', () {
    test('нажали «собачку» — панель обязана ответить, даже если записей нет', () {
      expect(mentionPanelVisible(''), isTrue);
    });

    test('запрос ни с чем не совпал — панель остаётся и говорит об этом', () {
      expect(mentionPanelVisible('чего-то_такого_нет'), isTrue);
    });

    test('без запроса панели нет', () {
      expect(mentionPanelVisible(null), isFalse);
    });
  });

  group('нажатие на «собачку»', () {
    test('пустое поле получает @ и курсор за ним', () {
      final v = mentionTriggerValue('');
      expect(v.text, '@');
      expect(v.selection.baseOffset, 1);
    });

    test('к слову дописывается через пробел', () {
      expect(mentionTriggerValue('привет').text, 'привет @');
    });

    test('лишний пробел не удваивается', () {
      expect(mentionTriggerValue('привет ').text, 'привет @');
    });

    test('повторное нажатие не плодит собачек', () {
      expect(mentionTriggerValue('привет @').text, 'привет @');
    });

    test('текст и курсор едут ОДНИМ значением', () {
      // Два присваивания подряд (сперва text, потом selection) отправляют в
      // клавиатуру промежуточное состояние с курсором -1. На iOS система на
      // это отвечает своим значением, и набранное откатывается.
      final v = mentionTriggerValue('привет');
      expect(v.selection.baseOffset, v.text.length);
      expect(v.composing, TextRange.empty);
    });
  });
}
