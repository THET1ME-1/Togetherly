import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:shared_preferences/shared_preferences.dart';

import '../dict_strings.dart';
import '../utils/notification_permission.dart';
import 'locale_service.dart';
import 'notif_renderer.dart';

/// Локальное уведомление «капсула времени открылась» на дату [DateTime] открытия.
/// Планируется через `zonedSchedule` (системный будильник срабатывает и при
/// закрытом приложении — фоновый код не нужен, iOS-ограничения не мешают).
/// Планируется на устройстве автора при создании и на устройстве партнёра при
/// получении капсулы из realtime-ленты; id стабилен по memoryId → идемпотентно.
class CapsuleNotificationService {
  CapsuleNotificationService._();
  static final CapsuleNotificationService instance =
      CapsuleNotificationService._();

  static const String _channelId = 'time_capsule';
  static String get _channelName => ruEn('Капсула времени', 'Time capsule');
  static String get _channelDescription => ruEn(
      'Напоминание об открытии капсулы времени',
      'A reminder when a time capsule opens');

  /// Ключ, в котором ждёт капсула, к которой человек шёл из уведомления.
  /// Лента откроет её сама при первом показе.
  static const String pendingKey = 'capsule_pending_memory_id';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  final Set<int> _scheduled = <int>{};

  /// Нажали на уведомление: запоминаем капсулу, чтобы лента открыла именно её.
  ///
  /// Раньше payload'а не было вовсе — уведомление просто поднимало приложение
  /// на главный экран, и человек искал капсулу сам. А искать было негде:
  /// запечатанная за месяцы до срока, она лежала в ленте по дате создания
  /// (жалоба 31.08.2026: «капсулу нигде не найти и не открыть»).
  Future<void> _remember(String? memoryId) async {
    if (memoryId == null || memoryId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pendingKey, memoryId);
    } catch (e) {
      debugPrint('CapsuleNotificationService: капсула не запомнилась — $e');
    }
  }

  /// Капсула, которую ждёт человек, и снятие метки: открываем один раз.
  Future<String?> takePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(pendingKey);
      if (id != null && id.isNotEmpty) await prefs.remove(pendingKey);
      return id;
    } catch (e) {
      return null;
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        _remember(response.payload);
      },
    );
    // Приложение могли поднять самим нажатием — забираем payload и оттуда.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      await _remember(launch?.notificationResponse?.payload);
    }
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    if (Platform.isIOS || Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    _initialized = true;
  }

  /// Планирует уведомление на [openAt]. Повторные вызовы с тем же memoryId —
  /// no-op (id стабилен). Прошедшие даты игнорируются.
  Future<void> schedule(String memoryId, DateTime openAt,
      {String? capsuleTitle}) async {
    final id = idForMemory(memoryId);
    if (_scheduled.contains(id)) return;
    if (!openAt.isAfter(DateTime.now())) return;
    // Помечаем СРАЗУ: каждую капсулу планируем максимум один раз за сессию, даже
    // если платформенный вызов упадёт. Иначе стрим-листенер ленты (зовёт schedule
    // на КАЖДУЮ эмиссию) при неудаче гонял бы тяжёлый init()/tz.initializeTimeZones
    // заново на каждой эмиссии, забивая isolate и не давая outbox-флашу
    // завершиться — это читалось как «бесконечная синхронизация».
    _scheduled.add(id);
    try {
      if (!_initialized) await init();
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await requestNotificationPermissionSafely(androidPlugin);
      final s = LocaleService.current;
      final body = (capsuleTitle != null && capsuleTitle.trim().isNotEmpty)
          ? s.capsuleOpenedBodyNamed(capsuleTitle.trim())
          : s.capsuleOpenedBody;
      // Android — видом «А» (`NotifAlarm`): ссылка несёт номер капсулы, и
      // лента откроет именно её. Иначе — плагином, с номером в payload.
      await NotifRenderer.schedule(
        plugin: _plugin,
        id: id,
        kind: 'capsule',
        ctx: {'capsule_id': memoryId},
        channel: _channelId,
        title: s.capsuleOpenedTitle,
        body: body,
        when: tz.TZDateTime.from(openAt, tz.local),
        details: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/ic_notification',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        // Payload — id капсулы: по нему лента откроет именно её.
        payload: memoryId,
        // Неточный режим: не требует спец-разрешения SCHEDULE_EXACT_ALARM
        // (Android 13+ иначе кидает исключение). Для капсулы, открывающейся через
        // недели/месяцы, окно в пару часов несущественно.
        mode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('CapsuleNotificationService.schedule failed: $e');
    }
  }

  /// Стабильный положительный id из memoryId (не пересекается с фиксированными
  /// id других сервисов, напр. 9991 маскота). Статический — покрыт тестами.
  static int idForMemory(String memoryId) {
    var h = 0;
    for (final c in memoryId.codeUnits) {
      h = (h * 31 + c) & 0x3FFFFFFF;
    }
    return 100000 + (h % 800000);
  }
}
