import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_couple_art.dart';

void main() {
  group('картинка пары в виджете', () {
    test('две девушки', () {
      expect(coupleArtFor('female', 'female'), 'widget_couple_ff');
    });

    test('двое парней', () {
      expect(coupleArtFor('male', 'male'), 'widget_couple_mm');
    });

    test('парень и девушка', () {
      expect(coupleArtFor('male', 'female'), 'widget_couple_mf');
    });

    test('пустой пол даёт пару по умолчанию — потому его и нельзя писать', () {
      expect(coupleArtFor('female', ''), 'widget_couple_mf');
      expect(coupleArtFor('', ''), 'widget_couple_mf');
    });
  });

  group('запись пола в ключи виджета', () {
    test('известный пол пишем', () {
      expect(shouldWriteGender('female'), isTrue);
      expect(shouldWriteGender('male'), isTrue);
    });

    test('пустым не затираем прежнее значение', () {
      expect(shouldWriteGender(''), isFalse);
    });
  });

  test('сервис виджетов не пишет пол вслепую', () {
    // Сторож ровно того случая, что был: `syncTimerAndDays` клал в ключи
    // `_cachedMyGender`/`_cachedPartnerGender` без проверки, а зовётся он и до
    // того, как кэш заполнен. Пустая строка перебивала верный пол.
    final src = File('lib/services/home_widget_service.dart').readAsStringSync();
    final lines = src.split('\n');
    var found = 0;
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('_gender\'')) continue;
      found++;
      final around = lines.sublist(i - 4 < 0 ? 0 : i - 4, i + 1).join('\n');
      expect(around.contains('shouldWriteGender'), isTrue,
          reason: 'строка ${i + 1}: пол пишется без проверки на пустоту, '
              'а пустая строка нарисует паре по умолчанию мальчика');
    }
    expect(found, greaterThan(0), reason: 'запись пола вообще не найдена');
  });
}
