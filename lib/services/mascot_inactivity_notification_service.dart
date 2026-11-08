import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class MascotInactivityNotificationService {
  MascotInactivityNotificationService._();

  static final MascotInactivityNotificationService instance =
      MascotInactivityNotificationService._();

  static const int _notificationId = 9991;
  static const String _channelId = 'mascot_miss_you';
  static const String _channelName = 'Маскот';

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
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Напоминание, если вы давно не открывали приложение',
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
      await _plugin.cancel(id: _notificationId);
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

      await _plugin.zonedSchedule(
        id: _notificationId,
        title: 'Ваш маскот скучает 🥺',
        body: 'Ты так давно не заходил — войди и обрадуй маскотика 🐾',
        scheduledDate: scheduledAt,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Напоминание, если вы давно не открывали приложение',
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('MascotInactivityNotificationService.schedule failed: $e');
    }
  }
}
