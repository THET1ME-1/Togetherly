import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'pb_push_service.dart';
import 'pocketbase_service.dart';

/// Фоновая доставка пуш-уведомлений БЕЗ FCM (§5 cutover Firebase→PocketBase).
///
/// [PbPushService] держит SSE-подписку на активность партнёра (чат/настроение/
/// «скучаю») и поднимает локальные уведомления. Пока приложение открыто, эта
/// подписка живёт в главном изоляте (см. `home_screen`). Но когда приложение
/// свёрнуто или выгружено из недавних, главный изолят усыпляется/убивается и
/// SSE-сокет рвётся — пуши перестают доходить. Этот сервис закрывает разрыв:
/// держит Android foreground-сервис (тип `dataSync`) с ОТДЕЛЬНЫМ изолятом, в
/// котором тот же [PbPushService] продолжает слушать сервер, пока пара активна.
///
/// Сервис запускается, пока приложение НА ПЕРЕДНЕМ ПЛАНЕ (на home-экране после
/// привязки пары) — иначе Android 12+ заблокировал бы старт foreground-сервиса
/// из фона. Дальше он переживает сворачивание и свайп из недавних.
///
/// iOS НЕ поддерживается: постоянный фоновый сокет там не выживает (нужен
/// APNs — отдельная задача). На iOS пуши работают только пока приложение
/// открыто, через главный изолят (см. `home_screen._updatePartnerPush`).
class PushBackgroundService {
  PushBackgroundService._();
  static final PushBackgroundService instance = PushBackgroundService._();
  factory PushBackgroundService() => instance;

  bool _configured = false;

  void _ensureConfigured() {
    if (_configured) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'partner_push_service',
        channelName: 'Связь с сервером',
        channelDescription:
            'Держит соединение, чтобы доставлять сообщения, настроение и '
            '«скучаю» от партнёра, пока приложение свёрнуто.',
        // Каналу/баннеру по умолчанию LOW importance + без вибрации/бейджа —
        // постоянное уведомление сервиса не мозолит глаза.
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // SSE — событийный, поллинг не нужен. Раз в минуту будим обработчик как
        // watchdog: если подписки не поднялись (сервис стартовал раньше, чем
        // восстановилась PB-сессия), пробуем снова.
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _configured = true;
  }

  /// Поднять фоновую доставку для активной пары. Идемпотентно, только Android.
  /// Зовётся, пока приложение на переднем плане (см. ограничение в доке класса).
  Future<void> start({
    required String groupId,
    required String myUid,
    required String partnerUid,
    String partnerName = 'Партнёр',
  }) async {
    if (!Platform.isAndroid) return;
    if (groupId.isEmpty || myUid.isEmpty || partnerUid.isEmpty) return;
    _ensureConfigured();

    // Контекст пары для изолята обработчика — он прочитает его в onStart.
    await FlutterForegroundTask.saveData(key: _kGroupId, value: groupId);
    await FlutterForegroundTask.saveData(key: _kMyUid, value: myUid);
    await FlutterForegroundTask.saveData(key: _kPartnerUid, value: partnerUid);
    await FlutterForegroundTask.saveData(key: _kPartnerName, value: partnerName);

    if (await FlutterForegroundTask.isRunningService) return;

    // Разрешение на уведомления (А13+) — без него сервис не покажет ни иконку,
    // ни баннеры. Запрашиваем из главного изолята (UI), пока есть контекст.
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      serviceId: 4711,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Togetherly на связи',
      notificationText: 'Получаем уведомления от партнёра',
      callback: pushServiceCallback,
    );
  }

  /// Остановить фоновую доставку (выход из аккаунта / распад пары).
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

const String _kGroupId = 'push_group_id';
const String _kMyUid = 'push_my_uid';
const String _kPartnerUid = 'push_partner_uid';
const String _kPartnerName = 'push_partner_name';

/// Точка входа изолята foreground-сервиса. ДОЛЖНА быть top-level + vm:entry-point
/// (её адрес передаётся нативной части при старте сервиса).
@pragma('vm:entry-point')
void pushServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_PushTaskHandler());
}

class _PushTaskHandler extends TaskHandler {
  bool _started = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _bootstrap();
  }

  /// Поднять PB-сессию и SSE-подписки В ИЗОЛЯТЕ СЕРВИСА. Идемпотентно —
  /// выходит сразу, если уже поднято.
  Future<void> _bootstrap() async {
    if (_started) return;
    try {
      final groupId =
          await FlutterForegroundTask.getData<String>(key: _kGroupId) ?? '';
      final myUid =
          await FlutterForegroundTask.getData<String>(key: _kMyUid) ?? '';
      final partnerUid =
          await FlutterForegroundTask.getData<String>(key: _kPartnerUid) ?? '';
      final partnerName =
          await FlutterForegroundTask.getData<String>(key: _kPartnerName) ??
              'Партнёр';
      if (groupId.isEmpty || partnerUid.isEmpty) return;

      // Изолят свежий — поднимаем клиент PB и восстанавливаем сессию из
      // SharedPreferences (тот же AsyncAuthStore, что и в главном изоляте;
      // токен уже на диске после входа). Свой getInstance читает с диска →
      // видит актуальную сессию.
      await PocketBaseService().init();
      if (!PocketBaseService().isLoggedIn) {
        return; // сессии ещё нет — повтор на watchdog (onRepeatEvent)
      }

      await PbPushService().init();
      await PbPushService().start(
        groupId: groupId,
        myUid: myUid,
        partnerUid: partnerUid,
        partnerName: partnerName,
      );
      _started = true;
      debugPrint('PushBackgroundService: SSE-подписки подняты (group=$groupId)');
    } catch (e) {
      debugPrint('PushBackgroundService bootstrap failed: $e');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // watchdog: если не поднялись (старт раньше входа) — пробуем снова.
    if (!_started) unawaited(_bootstrap());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await PbPushService().stop();
    _started = false;
  }
}
