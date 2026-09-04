// Нативный компрессор картинок обязан быть ограничен по времени.
//
// На части устройств (realme/ColorOS, Android 16 и не только) кодек
// `flutter_image_compress` зависает на некоторых снимках и НИКОГДА не
// возвращает future. `try/catch` такой вызов не ловит: зависший future не
// бросает исключение — он просто не завершается, и всё, что его ждёт, стоит
// навсегда.
//
// Один раз это уже разобрали и закрыли таймаутом в `MediaService.uploadFile`.
// В трёх других местах его не поставили, и одно из них лежит ровно на пути
// сохранения фото-виджета: `_saveCarouselForWidget` → `refreshPhotoOfDay` →
// `syncPhotoOfDayCarousel` → `_cachePhotoFromUrl` → `_shrinkForWidget`. Отсюда
// жалоба @hi_no_kate (04.09.2026): «После добавления фото бесконечная
// загрузка» — на видео кнопка «Сохранить» так и осталась крутящимся кружком.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('каждый вызов компрессора ограничен по времени', () {
    final offenders = <String>[];

    for (final file in files) {
      final source = file.readAsStringSync();
      var from = 0;
      while (true) {
        final at = source.indexOf('FlutterImageCompress.', from);
        if (at < 0) break;
        from = at + 1;
        // Вызов кончается там, где закрывается его список аргументов; ищем
        // `.timeout(` в хвосте — он ставится сразу за закрывающей скобкой.
        final tail = source.substring(at, (at + 900).clamp(0, source.length));
        if (tail.contains('.timeout(')) continue;
        final line = '\n'.allMatches(source.substring(0, at)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }

    expect(offenders, isEmpty,
        reason: 'зависший кодек не бросает исключение — ждать его нечем: '
            '${offenders.join(", ")}');
  });
}
