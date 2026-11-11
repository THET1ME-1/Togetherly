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

  // Запасная задача раз в 15 минут дублирует тихий пуш: изменения партнёра
  // приходят сразу, а она нужна там, где пуши не дошли. Замер: повторный
  // проход того же телефона приходил ровно через 15 минут круглые сутки.
  // Теперь задача сперва смотрит, давно ли виджеты обновлялись, и движок
  // Flutter поднимает только когда пора: при включённом экране раз в 14
  // минут, при выключенном раз в час.
  group('пора ли запасной задаче будить Dart', () {
    const minute = 60 * 1000;
    const now = 1000 * 60 * minute;

    bool due({required int minutesAgo, required bool screenOn}) => widgetTickDue(
          nowMs: now,
          refreshedAtMs: now - minutesAgo * minute,
          screenOn: screenOn,
        );

    test('экран включён: пора через 14 минут после прошлого обновления', () {
      expect(due(minutesAgo: 5, screenOn: true), isFalse, reason: 'пуш только что обновил виджеты');
      expect(due(minutesAgo: 13, screenOn: true), isFalse);
      expect(due(minutesAgo: 14, screenOn: true), isTrue);
      expect(due(minutesAgo: 40, screenOn: true), isTrue);
    });

    test('экран выключен: виджет никто не видит, пора только через час', () {
      expect(due(minutesAgo: 15, screenOn: false), isFalse);
      expect(due(minutesAgo: 59, screenOn: false), isFalse);
      expect(due(minutesAgo: 60, screenOn: false), isTrue);
    });

    test('когда обновляли, неизвестно — пора', () {
      expect(widgetTickDue(nowMs: now, refreshedAtMs: 0, screenOn: false), isTrue);
    });

    // Часы телефона перевели назад: отметка оказалась в будущем. Ждать её
    // нельзя, виджеты застыли бы на весь сдвиг.
    test('отметка из будущего — пора', () {
      expect(widgetTickDue(nowMs: now, refreshedAtMs: now + 5 * minute, screenOn: true), isTrue);
    });
  });

  group('запасная задача на Android', () {
    final tick = _kt('WidgetRefreshTick.kt');
    final activity = _kt('MainActivity.kt');

    test('правило и сроки в Kotlin те же, что под тестами в Dart', () {
      expect(tick, contains('FRESH_SCREEN_ON_MS = ${kWidgetFreshScreenOn.inMinutes} * 60 * 1000L'));
      expect(tick, contains('FRESH_SCREEN_OFF_MS = ${kWidgetFreshScreenOff.inMinutes} * 60 * 1000L'));
      expect(tick, contains('"$kWidgetsRefreshedAtKey"'), reason: 'Kotlin читает не ту отметку, что пишет Dart');
      expect(tick, contains('if (refreshedAtMs <= 0 || age < 0) return true'));
    });

    test('движок Flutter поднимает только после проверки', () {
      final work = tick.substring(tick.indexOf('override fun doWork()'));
      final widgets = work.indexOf('WidgetsOnScreen.any(');
      final due = work.indexOf('due(');
      final wake = work.indexOf('WidgetRefreshWake.enqueue(');
      expect(widgets, greaterThan(0));
      expect(widgets, lessThan(wake));
      expect(due, lessThan(wake), reason: 'Dart будится, не спросив, пора ли');
      expect(work, contains('isInteractive'));
    });

    // Пушу нужна пауза в шесть секунд, чтобы склеить пачку. Задача приходит
    // одна, а при выключенном экране телефон засыпает раньше, чем пауза
    // кончится: на эмуляторе обновление ждало следующего пробуждения.
    test('будит Dart сразу, без паузы на склейку пушей', () {
      final wake = _kt('WidgetRefreshWake.kt');
      expect(tick, contains('WidgetRefreshWake.enqueue(context, WidgetRefreshWake.TASK_ALL, gatherSeconds = 0)'));
      expect(wake, contains('.setInitialDelay(gatherSeconds, TimeUnit.SECONDS)'));
      expect(wake, contains('gatherSeconds: Long = GATHER_SEC'), reason: 'пуш потерял паузу на склейку');
    });

    test('ставится раз в 15 минут и не сбивает уже стоящую', () {
      expect(tick, contains('PeriodicWorkRequestBuilder<WidgetRefreshTick>(15, TimeUnit.MINUTES)'));
      expect(tick, contains('ExistingPeriodicWorkPolicy.KEEP'));
      expect(tick, contains('NetworkType.CONNECTED'));
    });

    test('приложение ставит и снимает её через канал виджетов', () {
      expect(activity, contains('"scheduleWidgetTick"'));
      expect(activity, contains('"cancelWidgetTick"'));
    });
  });

  group('отметка удачного прохода', () {
    final source = File('lib/services/home_widget_service.dart').readAsStringSync();

    test('проход пишет её после своих частей', () {
      final start = source.indexOf('Future<void> backgroundRefreshAll(');
      final body = source.substring(start, source.indexOf('\n  }\n', start));
      final parts = body.indexOf('_refreshAllParts(');
      final mark = body.indexOf('_markRefreshed(');
      expect(mark, greaterThan(parts), reason: 'отметка стоит до самого обновления');
    });

    // Не дозвонились — прохода, считай, не было: отметка осталась бы свежей,
    // и запасная задача час не трогала бы застывший виджет.
    test('сбой чтения отметку не ставит', () {
      final start = source.indexOf('Future<void> _markRefreshed(');
      final body = source.substring(start, source.indexOf('\n  }\n', start));
      final read = body.indexOf('await pass.rows(');
      final save = body.indexOf('kWidgetsRefreshedAtKey');
      expect(read, greaterThan(0));
      expect(read, lessThan(save));
    });
  });

  group('задача раз в 15 минут', () {
    final service =
        File('lib/services/widget_background_refresh_service.dart').readAsStringSync();

    test('не ставится, пока виджетов нет', () {
      final schedule = service.substring(service.indexOf('Future<void> _schedule()'));
      final check = schedule.indexOf('_refreshWanted()');
      final register = schedule.indexOf("'scheduleWidgetTick'");
      expect(check, greaterThan(0), reason: 'задача ставится, не спросив про виджеты');
      expect(register, greaterThan(0), reason: 'запасная задача не ставится вовсе');
      expect(check, lessThan(register));
    });

    // Задача пакета workmanager поднимала движок Flutter на каждый запуск.
    // Её место заняла нативная, прежнюю снимаем при первой же возможности.
    test('прежняя задача пакета больше не ставится и снимается', () {
      expect(service, isNot(contains('registerPeriodicTask(')));
      final schedule = service.substring(service.indexOf('Future<void> _schedule()'));
      expect(schedule, contains('_cancelPluginTask()'));
      final unschedule = service.substring(service.indexOf('Future<void> _unschedule()'));
      expect(unschedule.substring(0, unschedule.indexOf('\n  }\n')), contains("'cancelWidgetTick'"));
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
