// Журнал отрисовки виджета: что расширение успело сделать.
//
// Виджет живёт отдельным процессом, и в Bugsink пишет приложение, а не он.
// Поэтому расширение оставляет короткие записи в общем контейнере, а приложение
// при запуске забирает их и отправляет. Так мы узнаём то, чего не видно снаружи:
// на каком размере строился виджет, нашёлся ли файл, сколько он весит, удалось
// ли его разжать и сколько памяти оставалось процессу.
//
// Ради этого журнал и заведён: 18.08.2026 квадрат 1×1 не показывал фотографию,
// а средний и большой показывали ту же самую (жалоба тестера).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_render_log.dart';

void main() {
  test('строка разбирается в поля', () {
    final rows = parseWidgetRenderLog(
      '1755500000|small|self|path=1;bytes=482133;decoded=1;px=1200x1600;mem=24',
    );
    expect(rows, hasLength(1));
    expect(rows.first['размер'], 'small');
    expect(rows.first['виджет'], 'self');
    expect(rows.first['файл'], 'есть');
    expect(rows.first['вес'], '471 КБ');
    expect(rows.first['разжато'], 'да');
    expect(rows.first['пиксели'], '1200x1600');
    expect(rows.first['памяти оставалось'], '24 МБ');
  });

  test('несколько строк идут по порядку, свежие последними', () {
    final rows = parseWidgetRenderLog(
      '1|small|self|path=1;decoded=0\n2|medium|partner|path=1;decoded=1',
    );
    expect(rows, hasLength(2));
    expect(rows[0]['размер'], 'small');
    expect(rows[1]['размер'], 'medium');
    expect(rows[0]['разжато'], 'нет',
        reason: 'вот это и есть ответ: файл был, а картинка не собралась');
  });

  test('обрыв на середине виден по недостающему признаку', () {
    final rows = parseWidgetRenderLog('7|small|love|start=1');
    expect(rows.first['начал'], 'да');
    expect(rows.first.containsKey('разжато'), isFalse,
        reason: 'запись без конца означает, что расширение убили посередине');
  });

  test('видно, галерея это или рабочий стол', () {
    final rows = parseWidgetRenderLog(
      '9|small|ios_partner_photo_path|stage=snapshot;preview=1;path=1;bytes=1024',
    );
    expect(rows.first['этап'], 'снимок');
    expect(rows.first['галерея'], 'да',
        reason: 'след остаётся, даже если виджет ещё не стоит на столе');
    expect(rows.first['вес'], '1 КБ');
  });

  test('мусор не роняет разбор', () {
    expect(parseWidgetRenderLog(''), isEmpty);
    expect(parseWidgetRenderLog('  \n\n'), isEmpty);
    expect(parseWidgetRenderLog('без разделителей'), isEmpty);
  });

  test('журнал обрезается до последних записей', () {
    final many = List.generate(50, (i) => '$i|small|self|path=1').join('\n');
    expect(parseWidgetRenderLog(many).length, lessThanOrEqualTo(30),
        reason: 'в отчёт незачем тащить всю историю, важен хвост');
  });

  group('связка на месте', () {
    test('расширение пишет журнал, приложение его забирает и чистит', () {
      final swift =
          File('ios/TogetherlyWidget/SharedStore.swift').readAsStringSync();
      expect(swift, contains('enum WidgetRenderLog'));
      expect(swift, contains('os_proc_available_memory'),
          reason: 'по остатку памяти видно, упёрлись ли в потолок расширения');

      final dart =
          File('lib/services/widget_diagnostics.dart').readAsStringSync();
      expect(dart, contains('parseWidgetRenderLog'));
      expect(dart, contains(kWidgetRenderLogKey),
          reason: 'ключ журнала должен совпадать с тем, что пишет расширение');
      expect(dart, contains("saveWidgetData<String>(kWidgetRenderLogKey, '')"),
          reason: 'иначе один и тот же журнал уедет в отчёт десять раз подряд');
    });

    test('фото-виджеты и парный записывают размер, на котором рисуются', () {
      final photos =
          File('ios/TogetherlyWidget/PhotoWidgets.swift').readAsStringSync();
      expect(photos, contains('WidgetRenderLog.familyName'));
      final love =
          File('ios/TogetherlyWidget/LoveWidget.swift').readAsStringSync();
      expect(love, contains('WidgetRenderLog.write'));
    });
  });
}
