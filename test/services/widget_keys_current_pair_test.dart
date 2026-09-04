// Ключи виджета принадлежат одной паре.
//
// Жалобы 31.08–01.09.2026 от людей с несколькими парами: «в виджете аватарка
// другого человека, хотя по настроениям видно, что сейчас на виджете не он»,
// «почему настроения отображаются не от той группы, за которой закреплён
// виджет». Тексты и настроения уходят в ключи сразу, а фотографии и аватарки
// качаются в фоне — и поздний ответ от прежней пары дописывал её лицо поверх
// свежих текстов. Со стороны это выглядит как смесь двух пар в одном виджете.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/services/widget_service.dart').readAsStringSync();

  group('Запись картинок сверяется с текущей парой', () {
    test('_downloadPhoto принимает поколение привязки', () {
      expect(
        src.contains('Future<void> _downloadPhoto(\n    String? url,\n    String key, {\n    required int generation,\n  }) async {'),
        isTrue,
        reason: 'без поколения запись нечем отличить от устаревшей',
      );
    });

    test('внутри метода ключи пишутся только через проверку', () {
      final start = src.indexOf('Future<void> _downloadPhoto(');
      // Тело метода — до следующего заголовка раздела. Сама подготовка файла
      // переехала в HomeWidgetService (её просит и фоновое обновление), здесь
      // осталась запись ключа под сверку с текущей парой.
      final end = src.indexOf('\n  // ═══', start);
      final body = src.substring(start, end > 0 ? end : src.length);
      expect(body.contains('HomeWidget.saveWidgetData'), isFalse,
          reason: 'прямая запись обходит проверку пары');
      expect(body.contains('_saveIfCurrent('), isTrue);
    });

    test('проверка отказывает записи от прежней пары', () {
      final start = src.indexOf('Future<void> _saveIfCurrent(');
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 400);
      expect(body.contains('generation != _bindGeneration'), isTrue);
      expect(body.contains('return;'), isTrue);
    });

    test('каждый вызов передаёт поколение', () {
      // Все вызовы, кроме самого объявления и записей в журнал.
      final calls = RegExp(r'_downloadPhoto\(([^;]*?)\)', dotAll: true)
          .allMatches(src)
          .map((m) => m.group(1)!)
          .where((a) => !a.contains('String? url') && !a.contains(r'$key'))
          .toList();
      expect(calls.length, 5, reason: 'фото обоих, аватарки обоих и группа');
      for (final args in calls) {
        expect(args.contains('generation: bindGeneration'), isTrue,
            reason: 'вызов без сверки с текущей парой: $args');
      }
    });
  
    // Файл и запись кэша ведутся по ключу ПАРЫ. С общим ключом переключение
    // между связями сносило снимок предыдущей: уборка старых файлов удаляет
    // всё по тому же имени, а запись кэша указывает уже на чужую ссылку.
    test('картинка готовится по ключу пары, а не по общему', () {
      final start = src.indexOf('Future<void> _downloadPhoto(');
      final end = src.indexOf('\n  // ═══', start);
      final body = src.substring(start, end > 0 ? end : src.length);
      expect(body.contains('pairImagePath(pairWidgetKey(_groupId, key)'), isTrue,
          reason: 'иначе связи воюют за один файл');
    });
  });
}
