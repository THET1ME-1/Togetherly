// Задача склада не должна ждать сама себя.
//
// `WidgetPhotoStore` держит идущие закачки в карте `_inFlight`, чтобы два
// виджета не тянули один файл дважды. Снимать запись оттуда полагается в
// `whenComplete` — и вот там пряталась беда:
//
//     .whenComplete(() => _inFlight.remove(key))
//
// `Map.remove` возвращает СНЯТОЕ значение, а это сама текущая задача. Стрелка
// без фигурных скобок возвращает её из колбэка, а `whenComplete`, увидев
// future, начинает его ждать — задача ждёт собственного завершения и не
// завершается никогда. Байты при этом уже прочитаны: в логах видно, как файл
// берётся с диска, а тот, кто его просил, не дожидается.
//
// Наружу это выглядело так: тексты на виджете свежие, фотография прежняя.
// «В парном виджете не меняются фотографии, партнёр как поставил первую, так
// она и стоит… меняется только текст» (@Sanyaklick, 02.09.2026). Проверка на
// эмуляторе 08.09.2026: снимок меняли шесть раз подряд, ни один не доехал;
// после правки — доезжает за 300 мс.
//
// Тест держит две вещи: поведение самой конструкции и запрет на стрелку.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('колбэк whenComplete, вернувший ту же задачу, вешает её навсегда', () {
    // Воспроизводим ровно ту конструкцию на игрушечной карте.
    final inFlight = <String, Future<int>>{};
    late Future<int> job;
    var done = false;

    job = Future.value(1).whenComplete(() => inFlight.remove('k'));
    inFlight['k'] = job;
    unawaited(job.then((_) => done = true));

    // Ждём заведомо дольше, чем нужно исправной цепочке.
    return Future<void>.delayed(const Duration(milliseconds: 200), () {
      expect(done, isFalse,
          reason: 'именно так задача и зависала: колбэк вернул её саму');

      // А с телом в фигурных скобках всё проходит.
      final ok = <String, Future<int>>{};
      late Future<int> good;
      var goodDone = false;
      good = Future.value(1).whenComplete(() {
        ok.remove('k');
      });
      ok['k'] = good;
      unawaited(good.then((_) => goodDone = true));
      return Future<void>.delayed(const Duration(milliseconds: 200), () {
        expect(goodDone, isTrue);
      });
    });
  });

  test('в складе картинок стрелки с remove нет', () {
    final source =
        File('lib/services/widget_photo_store.dart').readAsStringSync();
    expect(
      RegExp(r'whenComplete\(\(\)\s*=>').hasMatch(source),
      isFalse,
      reason: 'колбэк обязан быть с телом, иначе он вернёт снятую задачу',
    );
  });
}
