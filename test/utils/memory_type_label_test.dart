// Типы воспоминаний видны пользователю в легенде статистики. Пропущенный тип
// показывался сырым идентификатором с сервера — «videoLink» и «location»
// уехали так в релиз.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/memory_type_label.dart';

void main() {
  group('memoryTypeLabel', () {
    test('у каждого известного типа есть подпись без camelCase', () {
      // Совпадение подписи с самим типом здесь законно: по-английски «photo»
      // так и читается. Ловим другое — идентификатор, попавший на экран как
      // есть: он выдаёт себя заглавной буквой в середине слова.
      final camel = RegExp(r'[a-z][A-Z]');
      for (final type in kMemoryTypes) {
        final label = memoryTypeLabel(type);
        expect(label, isNotEmpty, reason: 'тип "$type" без подписи');
        expect(
          camel.hasMatch(label),
          isFalse,
          reason: 'тип "$type" показывается сырым идентификатором',
        );
      }
    });

    test('составные идентификаторы не утекают в интерфейс', () {
      // Именно эти два уехали в релиз сырыми: остальные типы — одно слово и
      // выглядели как обычная подпись, а camelCase виден сразу.
      expect(memoryTypeLabel('videoLink'), isNot(contains('L')));
      expect(memoryTypeLabel('location'), isNot('location'));
    });

    test('незнакомый тип отдаётся как есть — лучше сырое, чем пустое', () {
      expect(memoryTypeLabel('quest'), 'quest');
    });
  });
}
