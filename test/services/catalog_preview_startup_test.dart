import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/catalog_service.dart';

/// Владелец 27.11.2026 (предпросмотр Нового года на своём аккаунте): в
/// таблице шансов зимнего сундука рамки и значки шли кодовыми именами
/// («ny_wreath_bell», «badge_winter_lantern») без картинок. Спрятанный до
/// сезона набор догружался, только если ответ предпросмотра поменялся с
/// прошлого запуска, — со второго запуска уже нет; а в первый запуск полный
/// каталог приходил позже и затирал догруженное.
void main() {
  test('набор предпросмотра догружается и тогда, когда ответ не поменялся', () async {
    final asked = <List<String>>[];
    await catalogStartup(
      full: () async {},
      preview: () async => false,
      sets: () => const ['winter'],
      loadSets: (s) async => asked.add(s),
    );
    expect(asked, [
      ['winter'],
    ]);
  });

  test('набор догружается после полного каталога, а не до него', () async {
    final order = <String>[];
    final full = Completer<void>();
    final run = catalogStartup(
      full: () => full.future.then((_) => order.add('full')),
      preview: () async => true,
      sets: () => const ['winter'],
      loadSets: (s) async => order.add('sets'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(order, isEmpty, reason: 'догрузка набора не ждёт полного каталога — он её затрёт');
    full.complete();
    await run;
    expect(order, ['full', 'sets']);
  });

  test('полный каталог не пришёл — набор всё равно догружается', () async {
    final asked = <List<String>>[];
    await catalogStartup(
      full: () async => throw Exception('нет сети'),
      preview: () async => false,
      sets: () => const ['winter'],
      loadSets: (s) async => asked.add(s),
    );
    expect(asked, isNotEmpty);
  });

  test('без предпросмотра ничего лишнего не грузится', () async {
    final asked = <List<String>>[];
    await catalogStartup(
      full: () async {},
      preview: () async => false,
      sets: () => const [],
      loadSets: (s) async => asked.add(s),
    );
    expect(asked, isEmpty);
  });
}
