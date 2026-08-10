import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/locale_service.dart';

/// Каркас семи языков.
///
/// Строки живут в словаре `kStrings` (ключ → язык → строка), поэтому новый язык
/// это колонка, а не класс на полторы тысячи членов: семь таких классов дали бы
/// файл в пятьдесят тысяч строк, который никто не отредактирует.
///
/// Главное свойство каркаса — откат. Пока пять языков не наполнены, немец видит
/// английскую надпись, а не пустое место и не имя ключа; тест держит именно это.
void main() {
  group('словарь', () {
    test('русский и английский заполнены у каждого ключа', () {
      final broken = <String>[];
      for (final entry in kStrings.entries) {
        final ru = entry.value['ru'];
        final en = entry.value['en'];
        if (ru == null || ru.isEmpty) broken.add('${entry.key}: нет ru');
        if (en == null || en.isEmpty) broken.add('${entry.key}: нет en');
      }
      expect(broken, isEmpty, reason: broken.take(10).join('; '));
      // Порядок величины, а не точное число: словарь будет расти.
      expect(kStrings.length, greaterThan(1400));
    });

    test('непереведённый язык откатывается на английский', () {
      const key = 'save';
      expect(trDict(key, 'ru'), kStrings[key]!['ru']);
      // Код языка, которого в словаре нет заведомо: так проверка живёт и после
      // того, как de, fr, es, it и pt наполнятся.
      expect(trDict(key, 'zz'), kStrings[key]!['en'], reason: 'откат сломан');
      for (final code in ['de', 'fr', 'es', 'it', 'pt']) {
        final own = kStrings[key]![code];
        expect(
          trDict(key, code),
          own ?? kStrings[key]!['en'],
          reason: 'язык $code берёт не свою строку',
        );
      }
    });

    test('немецкий переведён целиком', () {
      // Немецкий — первый язык после ru/en, который наполнен полностью
      // (10 августа 2026, 1419 ключей). Пропуск здесь означает, что новую
      // строку завели без перевода: экран покажет английскую надпись посреди
      // немецкого интерфейса.
      final missing = kStrings.entries
          .where((e) => (e.value['de'] ?? '').isEmpty)
          .map((e) => e.key)
          .toList();
      expect(
        missing,
        isEmpty,
        reason: 'без немецкого перевода: ${missing.take(15).join(', ')}',
      );
    });

    test('неизвестный ключ отдаёт сам ключ, а не пустоту', () {
      expect(trDict('нет_такого_ключа', 'ru'), 'нет_такого_ключа');
    });

    test('ни один язык не отдаёт пустую строку', () {
      for (final lang in AppLanguage.values) {
        for (final key in kStrings.keys) {
          expect(
            trDict(key, lang.code),
            isNotEmpty,
            reason: 'пустая строка: $key / ${lang.code}',
          );
        }
      }
    });
  });

  group('язык устройства', () {
    test('по коду языка', () {
      expect(LocaleService.detect(const Locale('de')), AppLanguage.de);
      expect(LocaleService.detect(const Locale('pt', 'BR')), AppLanguage.pt);
      expect(LocaleService.detect(const Locale('ru', 'KZ')), AppLanguage.ru);
    });

    test('по стране, когда язык системы нам незнаком', () {
      // Швейцарский ретороманский нам неизвестен, а страна говорит по-немецки.
      expect(LocaleService.detect(const Locale('rm', 'CH')), AppLanguage.de);
      expect(LocaleService.detect(const Locale('ca', 'ES')), AppLanguage.es);
    });

    test('незнакомый язык и незнакомая страна — английский', () {
      expect(LocaleService.detect(const Locale('ja', 'JP')), AppLanguage.en);
    });

    test('код языка разбирается обратно', () {
      for (final lang in AppLanguage.values) {
        expect(AppLanguage.byCode(lang.code), lang);
      }
      expect(AppLanguage.byCode('zz'), isNull);
    });

    test('семь языков доезжают до MaterialApp', () {
      expect(LocaleService.supportedLocales.length, AppLanguage.values.length);
      expect(
        LocaleService.supportedLocales.map((l) => l.languageCode),
        containsAll(['ru', 'en', 'de', 'fr', 'es', 'it', 'pt']),
      );
    });
  });

  test('строки не вернулись обратно в классы', () {
    // Классы-близнецы на язык — та самая ловушка, из которой этот каркас и
    // вырос: с семью языками файл вырос бы до пятидесяти тысяч строк.
    final source = File('lib/services/locale_service.dart').readAsStringSync();
    final inClasses = RegExp(r"String get \w+ => '").allMatches(source).length;
    expect(
      inClasses,
      lessThan(20),
      reason: 'простые строки снова пишут в классы вместо словаря',
    );
  });
}
