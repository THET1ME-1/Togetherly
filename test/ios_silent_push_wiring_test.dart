import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож фонового обновления виджетов на iPhone.
///
/// У WidgetKit фонового обновления нет: пока приложение закрыто, фото и статус
/// партнёра на рабочем столе застывают до следующего запуска. Закрывает это
/// цепочка из четырёх звеньев, и обрыв любого из них выглядит одинаково —
/// «виджет не обновляется», без единой ошибки в логах:
///
///   хук `widget_data` → релей (`content-available`, priority 5)
///   → `AppDelegate` (безголовый движок) → Dart `widgetPushRefresh`.
///
/// Проверить это на Linux нечем, поэтому сверяем сами исходники: имена точки
/// входа и канала должны совпадать по обе стороны моста.
void main() {
  String read(String path) => File(path).readAsStringSync();

  final appDelegate = read('ios/Runner/AppDelegate.swift');
  final mainDart = read('lib/main.dart');
  final relay = read('pocketbase/apns/apns_relay.py');
  final pushModule = read('pocketbase/pb_hooks/apns_push.js');
  final pushHook = read('pocketbase/pb_hooks/push_apns.pb.js');
  final infoPlist = read('ios/Runner/Info.plist');

  test('приложению разрешено просыпаться от пуша', () {
    expect(infoPlist.contains('remote-notification'), isTrue,
        reason: 'Без UIBackgroundModes тихий пуш не будит приложение');
  });

  test('точка входа названа одинаково в Swift и в Dart', () {
    expect(appDelegate.contains('run(withEntrypoint: "widgetPushRefresh")'),
        isTrue);
    expect(mainDart.contains("@pragma('vm:entry-point')"), isTrue);
    expect(mainDart.contains('Future<void> widgetPushRefresh()'), isTrue,
        reason: 'Swift зовёт эту функцию по имени');
  });

  test('канал «готово» один и тот же с обеих сторон', () {
    expect(appDelegate.contains('love_app/widget_bg_refresh'), isTrue);
    expect(mainDart.contains('love_app/widget_bg_refresh'), isTrue);
    expect(mainDart.contains("invokeMethod('done'"), isTrue,
        reason: 'Без ответа iOS считает пробуждение неудачным');
  });

  test('пробуждение не остаётся без ответа', () {
    // Невызванный completionHandler Apple наказывает урезанием времени в
    // следующий раз, поэтому в Swift обязан быть таймаут.
    expect(appDelegate.contains('backgroundTimeout'), isTrue);
    expect(appDelegate.contains('.noData'), isTrue);
  });

  test('тихий пуш уходит с приоритетом 5 и типом background', () {
    // С приоритетом 10 Apple отвечает отказом на background-пуш.
    expect(relay.contains('"5" if push_type == "background" else "10"'), isTrue);
    expect(relay.contains('"content-available": 1'), isTrue);
    expect(relay.contains('push_type="background" if req.get("silent")'), isTrue);
  });

  test('сервер будит партнёра на изменение данных виджетов', () {
    expect(pushModule.contains('function wakeUp('), isTrue);
    expect(pushModule.contains('MIN_WAKE_GAP_MS'), isTrue,
        reason: 'Apple лимитирует тихие пуши — нужен разрыв между ними');
    expect(pushHook.contains('"widget_data"'), isTrue);
    expect(pushHook.contains('wakeGroup('), isTrue);
  });

  test('фоновое обновление больше не заперто на Android', () {
    final service = read('lib/services/home_widget_service.dart');
    expect(service.contains('if (!Platform.isAndroid && !Platform.isIOS) return;'),
        isTrue);
    expect(service.contains('_refreshIosPhotoWidgetsFromServer'), isTrue,
        reason: 'Иначе в фоне обновится всё, кроме фото-виджетов');
  });
}
