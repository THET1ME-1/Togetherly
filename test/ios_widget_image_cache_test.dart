import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Расширению виджета система отводит около 30 МБ на всё, а картинку оно
/// разжимает внутри `body` — SwiftUI строит его многократно (снимок, таймлайн,
/// галерея, каждое семейство), и один и тот же файл декодируется заново.
///
/// В журнале с ночи выхода 1.29.6 это видно построчно: фото партнёра
/// (453 КБ, 713×951) разжимается пять раз подряд, память падает 25 → 20 МБ и
/// не возвращается, на очередном заходе процесс убивают — виджет остаётся
/// пустым. Лечится кэшем разжатых кадров внутри процесса.
///
/// Тест сторожит форму решения по исходникам: XCTest в этом проекте не гоняется,
/// а сломать это можно одной правкой.
void main() {
  final store = File('ios/TogetherlyWidget/SharedStore.swift');
  late String src;

  setUpAll(() {
    expect(store.existsSync(), isTrue, reason: 'нет ${store.path}');
    src = store.readAsStringSync();
  });

  test('кэш разжатых кадров существует', () {
    expect(
      src.contains('enum WidgetImageCache'),
      isTrue,
      reason: 'без кэша каждый повторный build декодирует файл заново',
    );
  });

  test('загрузка спрашивает кэш ДО декодирования', () {
    final load = src.indexOf('static func load(');
    final decode = src.indexOf('CGImageSourceCreateThumbnailAtIndex');
    final ask = src.indexOf('WidgetImageCache.image(', load);
    expect(load, greaterThan(-1));
    expect(ask, greaterThan(-1), reason: 'load не заглядывает в кэш');
    expect(ask, lessThan(decode), reason: 'кэш спрашивается после разжатия');
  });

  test('ключ кэша включает время правки и размер файла', () {
    // Иначе новое фото не подхватится: путь у него тот же, и виджет застрянет
    // на прежнем снимке до перезапуска расширения.
    final key = RegExp(r'static func key\([\s\S]{0,600}?\n    \}').firstMatch(src);
    expect(key, isNotNull, reason: 'нет сборки ключа кэша');
    final body = key!.group(0)!;
    expect(body.contains('modificationDate') || body.contains('mtime'), isTrue,
        reason: 'ключ не смотрит на время правки файла');
    expect(body.contains('size'), isTrue, reason: 'ключ не смотрит на размер');
  });

  test('кэш ограничен по числу кадров', () {
    expect(
      RegExp(r'(limit|maxEntries)\s*(=|:)\s*\d').hasMatch(src),
      isTrue,
      reason: 'без потолка кэш сам съест те же 30 МБ',
    );
  });

  test('запрошенный размер округляется — иначе кэш промахивается', () {
    // GeometryReader отдаёт дробные точки, и без ступени ключ каждый раз новый.
    expect(RegExp(r'ceil\(maxSide / step\)').hasMatch(src), isTrue,
        reason: 'размер не приводится к ступени');
  });

  test('повторная выдача из кэша не пишет в журнал «начал»', () {
    // Запись со `start` без `decoded` означает «процесс убили посередине».
    // Если писать её на каждый заход в кэш, вердикт станет врать.
    final load = src.substring(src.indexOf('static func load('));
    final cached = load.indexOf('WidgetImageCache.image(');
    final start = load.indexOf('facts["start"]');
    expect(cached, lessThan(start),
        reason: 'выдача из кэша попадает в журнал как начало разжатия');
  });
}
