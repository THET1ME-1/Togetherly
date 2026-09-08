// Подготовка картинки для виджета обязана иметь предел по времени.
//
// Путь один и тот же для всех виджетов: взять байты (склад → диск или сеть),
// ужать кодеком, записать файл, отдать путь в контейнер. Каждый из этих шагов
// на живом телефоне умеет не вернуться вовсе — зависший future исключения не
// бросает, и `try/catch` его не ловит.
//
// Цена такой заминки видна на рабочем столе. Тексты уходят на виджет раньше
// картинок, поэтому виджет обновляется наполовину: статус и сообщение свежие,
// фотография прежняя. Так это и описывают: «в парном виджете не меняются
// фотографии, меняется только текст». Проверено на эмуляторе 08.09.2026 —
// снимок партнёра меняли пять раз подряд, доехал только первый.
//
// Правило: у каждой подготовки есть общий предел, а у обращений к диску и
// мосту виджета — свой. Сорвались — оставляем прежний снимок и пробуем ещё раз
// (повтор живёт в WidgetService._cachePhotosForWidget), но НЕ ждём вечно.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final store = File('lib/services/widget_photo_store.dart').readAsStringSync();
  final home = File('lib/services/home_widget_service.dart').readAsStringSync();
  final service = File('lib/services/widget_service.dart').readAsStringSync();

  test('выдача байтов ограничена по времени', () {
    expect(store.contains('_loadBudget'), isTrue,
        reason: 'у bytesFor должен быть общий предел');
    expect(store.contains('.timeout(_loadBudget'), isTrue);
    // Диск: чтение кэша и запись на склад.
    expect('.timeout(_diskStep)'.allMatches(store).length, greaterThanOrEqualTo(3),
        reason: 'кэш, чтение файла и запись на склад — каждый со своим пределом');
  });

  test('подготовка картинки парного виджета ограничена по времени', () {
    expect(home.contains('.timeout(_imageBudget)'), isTrue,
        reason: 'pairImagePath обязан укладываться в бюджет');
    expect(home.contains('_preparePairImage'), isTrue);
    // Диск и мост в контейнер.
    expect('.timeout(_ioStep)'.allMatches(home).length, greaterThanOrEqualTo(4));
  });

  test('снимок, не доехавший до виджета, пробуют ещё раз', () {
    expect(service.contains('_photoPathMissing'), isTrue,
        reason: 'без проверки пути повтор назначать не по чему');
    expect(service.contains('_photoRetryDelay'), isTrue);
    expect(service.contains('attempt: attempt + 1'), isTrue);
  });

  test('фон догоняет картинки, если не уложился в пробуждение', () {
    expect(home.contains('картинки догнали'), isTrue,
        reason: 'после таймаута закачка должна обновить виджет, когда закончит');
  });
}
