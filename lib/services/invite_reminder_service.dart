import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../utils/notification_permission.dart';
import 'locale_service.dart';

/// Напоминание тому, кто остался один.
///
/// По базе: 81,5% пар складываются в первый час после регистрации, и лишь 1,2% —
/// позже недели. Значит второй шанс у приглашения ровно один — следующий день,
/// пока человек ещё помнит, зачем ставил приложение. Дальше одиночка почти
/// наверняка уходит: 78,9% из них не возвращаются после дня установки.
///
/// Уведомление локальное: пуши через FCM в проекте отключены осознанно, а
/// напоминание себе самому сервера и не требует. Снимается, как только пара
/// появилась.
class InviteReminderService {
  InviteReminderService._();
  static final InviteReminderService instance = InviteReminderService._();

  static const int _notificationId = 9993;
  static const String _channelId = 'invite_reminder';
  static const String _channelName = 'Приглашение';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // Момент считаем относительным (now + сутки), поэтому зона тут ни на что
    // не влияет: тот же instant при любой local location. Базу зон всё равно
    // инициализируем — без неё `tz.local` бросает.
    tzdata.initializeTimeZones();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Напоминание позвать партнёра, пока пары нет',
        importance: Importance.defaultImportance,
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

  /// Пары нет — напомним завтра в это же время.
  ///
  /// Идемпотентно: один и тот же id, поэтому повторный запуск приложения
  /// переносит напоминание, а не плодит их.
  Future<void> scheduleIfSolo() async {
    if (!_initialized) await init();
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await requestNotificationPermissionSafely(androidPlugin);

      final s = LocaleService.current;
      await _plugin.zonedSchedule(
        id: _notificationId,
        title: s.inviteReminderTitle,
        body: s.inviteReminderBody,
        scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(days: 1)),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Напоминание позвать партнёра, пока пары нет',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@drawable/ic_notification',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('InviteReminderService.schedule failed: $e');
    }
  }

  /// Пара появилась — напоминание больше не нужно.
  Future<void> cancel() async {
    if (!_initialized) await init();
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('InviteReminderService.cancel failed: $e');
    }
  }
}
