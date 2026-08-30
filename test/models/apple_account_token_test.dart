import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/apple_account_token.dart';

void main() {
  group('метка аккаунта для App Store', () {
    test('формат UUID: Apple другого не примет', () {
      final t = appleAccountTokenFor('k32wyhvkfk9ifu1');
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
                r'[0-9a-f]{12}$')
            .hasMatch(t),
        isTrue,
        reason: t,
      );
    });

    test('одинаковая на всех устройствах человека', () {
      expect(appleAccountTokenFor('k32wyhvkfk9ifu1'),
          appleAccountTokenFor('k32wyhvkfk9ifu1'));
    });

    test('у разных людей разная', () {
      expect(appleAccountTokenFor('k32wyhvkfk9ifu1'),
          isNot(appleAccountTokenFor('z0ku06bzcfmxdc8')));
    });

    test('прежние идентификаторы Firebase тоже годятся', () {
      // Половина базы приехала из Firebase: смешанный регистр, до 28 символов.
      final t = appleAccountTokenFor('PIRTd2rptqedgGfJnYiSvZ1HVfM2');
      expect(t.length, 36);
    });

    test('пустой uid не даёт выдуманной метки', () {
      expect(appleAccountTokenFor(''), '');
    });

    test('значение прибито: смена ломает возвраты по прежним покупкам', () {
      // Эталон посчитан этой же функцией и зафиксирован намеренно. Красный
      // тест здесь означает, что менялось пространство имён или порядок байт,
      // а значит у купивших раньше метка стала другой.
      expect(appleAccountTokenFor('k32wyhvkfk9ifu1'),
          'feb81d38-13af-5fd5-b9cd-d7c79098ae29');
    });
  });
}
