// Виджету нельзя отдавать полноразмерные снимки.
//
// Расширению система отводит около 30 МБ, и `UIImage(contentsOfFile:)`
// разжимает файл целиком: снимок с камеры съедает под пятьдесят, расширение
// убивают, человек видит серый прямоугольник. Так пустовал маленький «Вместе»
// (13.08.2026) и квадратные виджеты 1×1 (18.08.2026), при том что средний и
// большой показывали ту же фотографию.
//
// Два конца: приложение кладёт в контейнер уже ужатые файлы, расширение читает
// их через ImageIO с ограничением по большей стороне (снимки, положенные
// прежними сборками, никуда не делись).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('расширение не читает картинки напрямую, мимо ограничителя', () {
    final dir = Directory('ios/TogetherlyWidget');
    final offenders = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.swift')) continue;
      final src = f.readAsStringSync();
      if (!src.contains('UIImage(contentsOfFile')) continue;
      // Единственное законное место — сам ограничитель: там это запасной путь
      // для формата, который ImageIO не осилил.
      if (f.path.endsWith('SharedStore.swift')) continue;
      offenders.add(f.path.split('/').last);
    }
    expect(offenders, isEmpty,
        reason: 'читать надо через WidgetImage.load: ${offenders.join(", ")}');
  });

  test('ограничитель на месте и жмёт по большей стороне', () {
    final src = File('ios/TogetherlyWidget/SharedStore.swift').readAsStringSync();
    expect(src, contains('CGImageSourceCreateThumbnailAtIndex'));
    expect(src, contains('kCGImageSourceThumbnailMaxPixelSize'));
  });

  test('приложение кладёт в контейнер ужатые файлы', () {
    // Подготовка картинки парного виджета живёт в HomeWidgetService: её просит
    // и служба на переднем плане, и фоновое обновление по тихому пушу.
    final src =
        File('lib/services/home_widget_service.dart').readAsStringSync();
    final start = src.indexOf('Future<String?> pairImagePath');
    expect(start, isNot(-1));
    // До следующего метода: тело `pairImagePath` длинное, окном не обойтись.
    final end = src.indexOf('Future<String?> pairEmojiPath', start);
    expect(end, isNot(-1));
    final body = src.substring(start, end);
    expect(body, contains('shrinkForWidget'),
        reason: 'иначе в парный виджет и аватарки уедет оригинал снимка');
  });
}
