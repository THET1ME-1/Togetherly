// Фото-виджеты на Android не обновлялись в фоне (19.09.2026).
//
// Список виджетов Dart спрашивал каналом `love_app/widgets`, а его
// регистрирует только MainActivity. В фоновых движках (WorkManager раз в
// 15 минут, пуш `refresh`, служба сокета) канала нет: вызов падал с
// MissingPluginException, список выходил пустым, и «Фото партнёра» с «Фото
// дня» менялись только при открытом приложении. Жалобы: обращения 12 и 162.
//
// Теперь сами виджеты при каждом обновлении кладут свои номера в
// HomeWidgetPreferences (WidgetIdRegistry.kt), и без канала Dart читает их
// оттуда через плагин home_widget — он есть в любом движке.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/home_widget_service.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('номера виджетов разбираются из записи и не падают на мусоре', () {
    expect(widgetIdsFromPrefs('[5,6]'), [5, 6]);
    expect(widgetIdsFromPrefs('["7", 8]'), [7, 8]);
    expect(widgetIdsFromPrefs(''), isEmpty);
    expect(widgetIdsFromPrefs(null), isEmpty);
    expect(widgetIdsFromPrefs('не json'), isEmpty);
    expect(widgetIdsFromPrefs('{"a":1}'), isEmpty);
  });

  final dart = _read('lib/services/home_widget_service.dart');
  final registry = _read(
      'android/app/src/main/kotlin/com/togetherly/love/WidgetIdRegistry.kt');

  const keys = {
    'getPhotoDayWidgetIds': 'widget_ids_photo_day',
    'getSelfPhotoWidgetIds': 'widget_ids_self_photo',
    'getPartnerPhotoWidgetIds': 'widget_ids_partner_photo',
    'getPhotoGridWidgetIds': 'widget_ids_photo_grid',
  };

  test('без канала главного окна список берётся из записи виджетов', () {
    keys.forEach((method, key) {
      final start = dart.indexOf('Future<List<int>> $method()');
      expect(start, greaterThan(0), reason: method);
      final body = dart.substring(start, dart.indexOf('\n  }\n', start));
      expect(body, contains('MissingPluginException'), reason: method);
      expect(body, contains("_widgetIdsFallback('$key')"), reason: method);
      expect(registry, contains('"$key"'), reason: 'натив не пишет $key');
    });
  });

  test('виджеты сами обновляют запись о себе', () {
    for (final f in ['PhotoDayWidgetProvider.kt', 'PhotoGridWidgetProvider.kt']) {
      final src = _read('android/app/src/main/kotlin/com/togetherly/love/$f');
      expect(RegExp(r'WidgetIdRegistry\.refresh\(').allMatches(src).length,
          greaterThanOrEqualTo(2),
          reason: '$f: нужно и в onUpdate, и в onDeleted');
    }
    final activity =
        _read('android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt');
    expect(activity, contains('WidgetIdRegistry.refresh('));
  });

  test('карусель в фоне пишет кадры сама, а не роняет обновление', () {
    final start = dart.indexOf("invokeMethod('updatePhotoDayCarousel'");
    final around = dart.substring(start - 200, start + 900);
    expect(around, contains('MissingPluginException'));
    expect(around, contains('_paths'));
    expect(around, contains('_current_index'));
  });
}
