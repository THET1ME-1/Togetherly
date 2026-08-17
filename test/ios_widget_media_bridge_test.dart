// Мост медиа виджетов должен быть в КАЖДОМ движке, включая фоновый.
//
// Связка Android — iOS, 17.08.2026: на Android парный виджет показывает обе
// половины с фотографиями, на iPhone обе половины пустые. Данные при этом на
// месте — Android читает те же записи, и в самом приложении фотографии видны.
//
// Ломался фоновый проход. Тихий пуш «обнови виджеты» поднимает отдельный
// headless-движок (`togetherly-widget-refresh`, точка входа `widgetPushRefresh`),
// и для него регистрировались только плагины из GeneratedPluginRegistrant. Канал
// `love_app/ios_widget_media` там не существовал, поэтому копирование файла в
// контейнер App Group падало с MissingPluginException. Dart эту ошибку глотает и
// записывает в ключ пустую строку — то есть каждое фоновое обновление СТИРАЛО
// фото с рабочего стола. На iOS приложение почти всегда выгружено, и виджеты
// живут именно фоновыми проходами, поэтому фотографии не появлялись вовсе.
//
// На Android мост не нужен: там путь к файлу отдаётся как есть.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

  /// Сколько раз в файле создаётся движок и сколько раз к нему привязывается мост.
  int count(String needle) => needle.allMatches(source).length;

  test('мост регистрируется столько же раз, сколько создаётся движок', () {
    final registrants = count('GeneratedPluginRegistrant.register');
    final bridges = count('setupWidgetMediaChannel(');
    // Одно объявление функции плюс по вызову на каждый движок.
    expect(
      bridges - 1,
      registrants,
      reason: 'движок без моста love_app/ios_widget_media затирает пути к фото '
          'пустой строкой: копирование в App Group падает с MissingPluginException',
    );
  });

  test('фоновый движок получает мост', () {
    // Ищем участок, где поднимается headless-движок обновления виджетов, и
    // проверяем, что мост привязан там же.
    final start = source.indexOf('togetherly-widget-refresh');
    expect(start, greaterThan(0), reason: 'не нашёл фоновый движок — разбор сломан');
    final tail = source.substring(start, (start + 1600).clamp(0, source.length));
    expect(
      tail,
      contains('setupWidgetMediaChannel'),
      reason: 'без моста фоновое обновление стирает фото парного виджета',
    );
  });
}
