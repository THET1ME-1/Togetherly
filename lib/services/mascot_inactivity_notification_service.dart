import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../dict_strings.dart';
import 'notif_renderer.dart';

class MascotInactivityNotificationService {
  MascotInactivityNotificationService._();

  static final MascotInactivityNotificationService instance =
      MascotInactivityNotificationService._();

  static const int _notificationId = 9991;
  static const String _channelId = 'mascot_miss_you';

  // Подписи на языке приложения: служба поднимается после выбора языка
  // (`LocaleService.init` в `main`), а канал при повторном создании
  // переименовывается у тех, кто уже видел русское название.
  static String get _channelName => ruEn('Маскот', 'Mascot');
  static String get _channelDescription => ruEn(
      'Напоминание, если вы давно не открывали приложение',
      "A reminder when you haven't opened the app for a while");

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosSettings = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings: settings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    // Разрешение здесь не спрашиваем (09.11.2026): этот сервис поднимается на
    // старте до входа и ставит напоминание при уходе в фон, в том числе когда
    // вход открывает страницу Google, и окно вылезало посреди входа.
    // Спрашивает главный экран, уже после входа.
    _initialized = true;
  }

  Future<void> markAppOpened() async {
    await cancelReminder();
  }

  Future<void> scheduleReminderAfterOneDay() async {
    await _scheduleReminder(const Duration(days: 1));
  }

  Future<void> cancelReminder() async {
    if (!_initialized) {
      await init();
    }
    try {
      await NotifRenderer.cancelScheduled(_plugin, _notificationId);
    } catch (e) {
      debugPrint('MascotInactivityNotificationService.cancel failed: $e');
    }
  }

  Future<void> _scheduleReminder(Duration delay) async {
    if (!_initialized) {
      await init();
    }

    try {
      // Без разрешения напоминание просто не покажется; просить его на уходе
      // в фон нельзя (см. init).
      final scheduledAt = tz.TZDateTime.now(tz.local).add(delay);

      // Android — видом «А» (`NotifAlarm`): иконка приложения, в развёрнутом
      // грустный Ту. Иначе — плагином, как раньше.
      await NotifRenderer.schedule(
        plugin: _plugin,
        id: _notificationId,
        kind: 'mascot_miss',
        channel: _channelId,
        title: ruEn('Ваш маскот скучает 🥺', 'Your mascot misses you 🥺'),
        body: ruEn('Ты так давно не заходил — войди и обрадуй маскотика 🐾',
            "It's been a while — come back and cheer up your mascot 🐾"),
        when: scheduledAt,
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
        mode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('MascotInactivityNotificationService.schedule failed: $e');
    }
  }
}
