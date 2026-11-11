import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import 'background_refresh_gate.dart';
import 'home_widget_service.dart';
import 'locale_service.dart';
import 'map/pair_map_widget_service.dart';
import 'network/server_route.dart';
import 'pocketbase_service.dart';
import 'push_arrivals.dart';

/// Периодический фоновый ФОЛБЭК обновления виджетов через WorkManager (Android).
///
/// С 1.43 задачу раз в 15 минут ведёт нативный `WidgetRefreshTick.kt`: он
/// решает, пора ли обновлять, до подъёма движка Flutter (TOG-90). Отсюда её
/// только ставят и снимают, а сам проход идёт в [widgetRefreshDispatcher].
/// Ниже — зачем этот запасной путь нужен вообще.
///
/// Мгновенное обновление виджетов при закрытом приложении держит
/// [PushBackgroundService] — foreground-сервис с Centrifugo-сокетом в отдельном
/// изоляте. Но на агрессивных OEM (Xiaomi/MIUI/HyperOS, Samsung One UI) система
/// усыпляет или убивает foreground-сервис ДАЖЕ с отключённой оптимизацией
/// батареи (у MIUI поверх батареи есть отдельный «Автозапуск» + своя чистка
/// памяти). Сокет рвётся → события партнёра не приходят → виджеты застывают до
/// открытия приложения.
///
/// Этот сервис — ВТОРОЙ, живучий канал: периодическая задача WorkManager
/// (минимум платформы — 15 мин), которая переживает убийство процесса и
/// запускается даже в Doze maintenance-окнах. Она сама тянет свежий widget_data
/// из PocketBase и перерисовывает виджеты — без сокета и без открытия
/// приложения. Не мгновенно (шаг ~15 мин), но гарантирует, что виджет не
/// застрянет навсегда, если foreground-сервис убили.
///
/// Android-only: на iOS WorkManager недоступен (там свой BGTaskScheduler —
/// отдельная задача). Контекст пары читается тем же способом, что и нативный
/// фоновый колбэк / изолят foreground-сервиса: PB-сессия с диска даёт myUid, а
/// groupId/partnerUid лежат в HomeWidget data (`love_widget_*`).
class WidgetBackgroundRefreshService {
  WidgetBackgroundRefreshService._();
  static final WidgetBackgroundRefreshService instance =
      WidgetBackgroundRefreshService._();

  /// Имя прежней задачи пакета workmanager: по нему её снимает и приложение,
  /// и сам фоновый проход.
  static const String periodicName = 'togetherly_widget_refresh';

  /// Разовая задача «перерисуй только карту» — её ставит нативный провайдер
  /// виджета «Где мы» (WidgetRefreshWake.kt), когда сменилась ячейка или
  /// картинки ещё нет. Имя сверяет test/android_widget_wake_test.dart.
  static const String mapTaskName = 'mapWidget';

  bool _initialized = false;

  /// Инициализация диспетчера WorkManager. Вызывать один раз из main() (Android).
  Future<void> init() async {
    if (!Platform.isAndroid || _initialized) return;
    try {
      await Workmanager().initialize(widgetRefreshDispatcher);
      _initialized = true;
    } catch (e) {
      debugPrint('WidgetBackgroundRefreshService.init failed: $e');
    }
  }

  StreamSubscription<void>? _inApp;
  Timer? _inAppGather;

  /// Пуш «данные виджетов поменялись», пришедший при открытом приложении.
  /// Нативная часть (FcmService) тогда не ставит задачу WorkManager — та
  /// поднимала бы второй движок Flutter на главном потоке, и слабые телефоны
  /// ловили «не отвечает» (1.41, 04.11.2026). Обновляет само приложение: тот
  /// же путь из PocketBase, что у фоновой задачи. Пачка пушей за пару секунд
  /// даёт одно обновление.
  void listenInApp() {
    if (!Platform.isAndroid || _inApp != null) return;
    _inApp = PushArrivals.instance.of('widgets').listen((_) {
      _inAppGather?.cancel();
      _inAppGather = Timer(const Duration(seconds: 2), () => unawaited(_refreshInApp()));
    });
  }

  Future<void> _refreshInApp() async {
    try {
      final myUid = PocketBaseService().userId ?? '';
      final groupId = await HomeWidget.getWidgetData<String>('love_widget_group_id') ?? '';
      final partnerUid = await HomeWidget.getWidgetData<String>('love_widget_partner_uid') ?? '';
      if (myUid.isEmpty || groupId.isEmpty) return;
      await HomeWidgetService.instance.backgroundRefreshAll(
        groupId: groupId,
        myUid: myUid,
        partnerUid: partnerUid,
        refreshPhotos: true,
      );
    } catch (e) {
      debugPrint('WidgetBackgroundRefreshService._refreshInApp failed: $e');
    }
  }

  /// Пара есть — фоновый рефреш нужен (ставит home_screen).
  bool _wanted = false;
  AppLifecycleListener? _life;

  /// Запланировать периодический рефреш. Пока приложение на экране, задачи
  /// нет: каждый её запуск поднимает второй движок Flutter на главном потоке,
  /// и слабый телефон показывал «не отвечает» прямо в открытом приложении
  /// (1.41, 04.11.2026). Виджеты в это время обновляет само приложение. Задача
  /// встаёт, когда приложение свернули, и снимается, когда вернулись.
  /// Вызывать при активной паре (см. home_screen._updatePartnerPush).
  Future<void> ensureScheduled() async {
    if (!Platform.isAndroid) return;
    _wanted = true;
    _life ??= AppLifecycleListener(
      onHide: () => unawaited(_schedule()),
      onShow: () => unawaited(_unschedule()),
    );
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.inactive) {
      await _unschedule();
    } else {
      await _schedule();
    }
  }

  /// Канал виджетов в MainActivity: там ставится и снимается нативная
  /// запасная задача (`WidgetRefreshTick.kt`).
  static const MethodChannel _native = MethodChannel('love_app/widgets');

  /// Задачу раз в 15 минут до 1.43 ставил пакет workmanager, и каждый её
  /// запуск поднимал движок Flutter (TOG-90). Она переживает обновление
  /// приложения, поэтому снимаем её при каждом случае.
  Future<void> _cancelPluginTask() async {
    try {
      await Workmanager().cancelByUniqueName(periodicName);
    } catch (e) {
      debugPrint('WidgetBackgroundRefreshService: прежняя задача не снялась — $e');
    }
  }

  Future<void> _unschedule() async {
    await _cancelPluginTask();
    try {
      await _native.invokeMethod<bool>('cancelWidgetTick');
    } catch (e) {
      debugPrint('WidgetBackgroundRefreshService._unschedule failed: $e');
    }
  }

  Future<void> _schedule() async {
    if (!_wanted) return;
    // Виджетов на столе нет — будить телефон раз в 15 минут незачем (TOG-90).
    // Поставят виджет — задача встанет при следующем сворачивании, а до того
    // его обновляет тихий пуш.
    if (!await _refreshWanted()) {
      await _unschedule();
      return;
    }
    await _cancelPluginTask();
    try {
      // Пока приложение было на экране, виджеты обновляло оно само: отметка
      // свежая, и запасная задача не станет будить Dart сразу после ухода.
      await HomeWidget.saveWidgetData<String>(
        kWidgetsRefreshedAtKey,
        '${DateTime.now().millisecondsSinceEpoch}',
      );
      // Нативная задача раз в 15 минут сама решает, пора ли будить Dart.
      await _native.invokeMethod<bool>('scheduleWidgetTick');
    } catch (e) {
      debugPrint('WidgetBackgroundRefreshService._schedule failed: $e');
    }
  }

  /// Отменить периодический рефреш (выход из аккаунта / распад пары).
  Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    _wanted = false;
    await _unschedule();
  }
}

/// Стоит ли на рабочем столе хоть один наш виджет: без них фоновое
/// обновление не нужно (правило — [backgroundRefreshWanted]).
Future<bool> _refreshWanted() async {
  int? count;
  try {
    count = (await HomeWidget.getInstalledWidgets()).length;
  } catch (e) {
    debugPrint('WidgetBackgroundRefreshService: число виджетов не узнали — $e');
  }
  return backgroundRefreshWanted(widgetsOnScreen: count);
}

/// Точка входа фонового изолята WorkManager. ДОЛЖНА быть top-level +
/// vm:entry-point (её адрес передаётся нативной части при initialize).
@pragma('vm:entry-point')
void widgetRefreshDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (!Platform.isAndroid) return true;
    try {
      // Фоновый изолят свежий — регистрируем плагины, иначе MethodChannel
      // (home_widget / shared_preferences / path_provider) недоступны.
      WidgetsFlutterBinding.ensureInitialized();
      await ServerRoute.install();
      // На Android no-op, но home_widget требует до первого saveWidgetData.
      await HomeWidget.setAppGroupId('group.com.togetherly.love');

      // Виджетов на столе нет — обновлять нечего. Задачу раз в 15 минут могла
      // поставить прежняя сборка или человек убрал последний виджет: снимаем
      // её здесь же, до сессии и сети (TOG-90).
      if (task != WidgetBackgroundRefreshService.mapTaskName && !await _refreshWanted()) {
        await Workmanager().cancelByUniqueName(WidgetBackgroundRefreshService.periodicName);
        return true;
      }

      // Восстанавливаем PB-сессию с диска (widget_data protected — нужен токен).
      await PocketBaseService().init();
      final myUid = PocketBaseService().userId ?? '';
      if (myUid.isEmpty) return true; // не залогинен — тихо выходим

      final groupId =
          await HomeWidget.getWidgetData<String>('love_widget_group_id') ?? '';
      final partnerUid =
          await HomeWidget.getWidgetData<String>('love_widget_partner_uid') ??
              '';
      // Карта «Где мы» рисуется и без пары (заглушка «подключите партнёра»),
      // поэтому её задача идёт раньше проверки группы.
      if (task == WidgetBackgroundRefreshService.mapTaskName) {
        await LocaleService.instance.init();
        await PairMapWidgetService.instance.refreshInBackground(
          groupId: groupId,
          myUid: myUid,
          partnerUid: partnerUid,
        );
        return true;
      }
      if (groupId.isEmpty) return true;

      // Единая точка фонового обновления всех виджетов из PB (та же, что в
      // изоляте foreground-сервиса). Сюда же приходит разовая задача
      // 'widgetRefresh' из тихого пуша (FcmService.kt).
      await HomeWidgetService.instance.backgroundRefreshAll(
        groupId: groupId,
        myUid: myUid,
        partnerUid: partnerUid,
        refreshPhotos: true,
      );
    } catch (e) {
      debugPrint('widgetRefreshDispatcher failed: $e');
    }
    // Всегда true: не помечаем задачу проваленной, чтобы WorkManager не уходил
    // в агрессивный backoff-ретрай — периодическое расписание и так вернётся.
    return true;
  });
}
