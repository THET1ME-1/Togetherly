// Телефон без наших виджетов на рабочем столе не просыпается ради них.
//
// TOG-90 (11.11.2026), отзыв Google Play: «91% батареи». Фоновая задача раз
// в 15 минут и тихий пуш «обнови виджеты» поднимали движок Flutter и слали
// семь запросов у каждого, кто в паре, даже когда на столе нет ни одного
// виджета. Замер на сервере: около 25 таких проходов в секунду, почти
// половина всех запросов. Обновлять там нечего, поэтому без виджетов задача
// не ставится, а пуш не будит Dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/background_refresh_gate.dart';

String _kt(String name) =>
    File('android/app/src/main/kotlin/com/togetherly/love/$name').readAsStringSync();

void main() {
  test('виджетов на столе нет — фоновое обновление не нужно', () {
    expect(backgroundRefreshWanted(widgetsOnScreen: 0), isFalse);
  });

  test('виджет стоит — обновление нужно', () {
    expect(backgroundRefreshWanted(widgetsOnScreen: 1), isTrue);
    expect(backgroundRefreshWanted(widgetsOnScreen: 7), isTrue);
  });

  // Система не ответила — ведём себя как раньше: застывший виджет хуже
  // лишнего пробуждения.
  test('число виджетов узнать не вышло — обновление остаётся', () {
    expect(backgroundRefreshWanted(widgetsOnScreen: null), isTrue);
  });

  group('тихий пуш на Android', () {
    final fcm = _kt('FcmService.kt');
    final gate = _kt('WidgetsOnScreen.kt');

    test('без виджетов на столе не ставит задачу, которая поднимает Dart', () {
      final check = fcm.indexOf('WidgetsOnScreen.any(applicationContext)');
      final wake = fcm.indexOf('WidgetRefreshWake.enqueue(');
      expect(check, greaterThan(0), reason: 'пуш будит Dart, не спросив про виджеты');
      expect(check, lessThan(wake), reason: 'проверка стоит после постановки задачи');
    });

    test('сбой проверки не глушит обновление', () {
      expect(gate, contains('catch (e: Exception)'));
      expect(gate, contains('true'), reason: 'при сбое проверки виджеты остались бы без обновления');
      expect(gate, contains('getInstalledProvidersForPackage'));
    });
  });

  group('задача раз в 15 минут', () {
    final service =
        File('lib/services/widget_background_refresh_service.dart').readAsStringSync();

    test('не ставится, пока виджетов нет', () {
      final schedule = service.substring(service.indexOf('Future<void> _schedule()'));
      final check = schedule.indexOf('_refreshWanted()');
      final register = schedule.indexOf('registerPeriodicTask(');
      expect(check, greaterThan(0), reason: 'задача ставится, не спросив про виджеты');
      expect(check, lessThan(register));
    });

    // Задача, поставленная прежней сборкой, живёт и после обновления. Она
    // снимает себя сама на первом же запуске, не дожидаясь входа в приложение.
    test('поставленная раньше снимает себя сама, не трогая сеть', () {
      final dispatcher = service.substring(service.indexOf('void widgetRefreshDispatcher()'));
      final check = dispatcher.indexOf('_refreshWanted()');
      final session = dispatcher.indexOf('PocketBaseService().init()');
      expect(check, greaterThan(0));
      expect(check, lessThan(session), reason: 'сессия и сеть поднимаются до проверки виджетов');
      expect(dispatcher, contains('cancelByUniqueName('));
    });

    // Карту «Где мы» будит её собственный виджет: он на столе точно есть.
    test('задача карты идёт мимо проверки', () {
      final dispatcher = service.substring(service.indexOf('void widgetRefreshDispatcher()'));
      final gateLine = dispatcher.indexOf('_refreshWanted()');
      final before = dispatcher.substring(0, gateLine);
      expect(before, contains('task != WidgetBackgroundRefreshService.mapTaskName'));
    });
  });
}
