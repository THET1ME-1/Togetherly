// Открытое приложение не поднимает второй движок Flutter ради виджетов
// (1.41, 04.11.2026). Задача WorkManager создаёт движок на главном потоке, и
// слабые телефоны (Techno Spark 20 Pro, Samsung A06/A35) ловили «приложение не
// отвечает» прямо в открытом приложении. Сторож сверяет исходники: правки
// стоят в Kotlin и в Dart, и разъезд ничем себя не выдаёт.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  const kotlin = 'android/app/src/main/kotlin/com/togetherly/love';

  test('пуш «виджеты» при открытом приложении идёт в Dart, а не в WorkManager', () {
    final fcm = _read('$kotlin/FcmService.kt');
    final toDart = fcm.indexOf('PushArrivedBridge.onScreen && PushArrivedBridge.attached');
    final toWork = fcm.indexOf('WidgetRefreshWake.enqueue(applicationContext, WidgetRefreshWake.TASK_ALL)');
    expect(toDart, greaterThan(0));
    expect(toWork, greaterThan(toDart), reason: 'проверка «на экране» обязана стоять раньше задачи');
  });

  test('MainActivity отмечает, что приложение на экране', () {
    final activity = _read('$kotlin/MainActivity.kt');
    expect(activity, contains('PushArrivedBridge.onScreen = true'));
    expect(activity, contains('PushArrivedBridge.onScreen = false'));
  });

  test('пачка пушей склеивается в один запуск фоновой задачи', () {
    // Пауза стала параметром: у пуша она прежняя, без неё идёт только
    // запасная задача раз в 15 минут (TOG-90).
    final wake = _read('$kotlin/WidgetRefreshWake.kt');
    expect(wake, contains('gatherSeconds: Long = GATHER_SEC'));
    expect(wake, contains('setInitialDelay(gatherSeconds'));
    expect(wake, contains('waitingUntil'));
    expect(_read('$kotlin/FcmService.kt'), isNot(contains('gatherSeconds')),
        reason: 'пуш обязан ждать соседей, свою паузу ему не задают');
  });

  test('приложение слушает сигнал «виджеты» и обновляет их само', () {
    final service = _read('lib/services/widget_background_refresh_service.dart');
    expect(service, contains("PushArrivals.instance.of('widgets')"));
    expect(_read('lib/main.dart'), contains('WidgetBackgroundRefreshService.instance.listenInApp()'));
  });

  test('пока приложение на экране, периодической задачи нет', () {
    final service = _read('lib/services/widget_background_refresh_service.dart');
    expect(service, contains('onShow: () => unawaited(_unschedule())'));
    expect(service, contains('onHide: () => unawaited(_schedule())'));
    // С 1.43 задача нативная (TOG-90): первый запуск через 15 минут после
    // ухода с экрана, а если её не успели снять, при открытом приложении она
    // Dart не будит.
    final tick = _read('$kotlin/WidgetRefreshTick.kt');
    expect(tick, contains('.setInitialDelay(15, TimeUnit.MINUTES)'));
    final work = tick.substring(tick.indexOf('override fun doWork()'));
    final onScreen = work.indexOf('PushArrivedBridge.onScreen && PushArrivedBridge.attached');
    expect(onScreen, greaterThan(0));
    expect(onScreen, lessThan(work.indexOf('WidgetRefreshWake.enqueue(')));
  });

  test('фоновое обновление будит плитки «Настроение» на Android', () {
    final widgets = _read('lib/services/home_widget_service.dart');
    final start = widgets.indexOf('Future<void> _refreshMoodWidgetFromServer(');
    final end = widgets.indexOf('Future<void> _refreshLockCountersFromServer(');
    expect(start, greaterThan(0));
    expect(widgets.substring(start, end), contains("'MoodTilesWidget2x2Provider', 'MoodTilesWidget4x2Provider'"));
  });
}
