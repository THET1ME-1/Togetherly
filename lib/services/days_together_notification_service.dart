import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/days_together_plan.dart';
import '../utils/notification_permission.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'locale_service.dart';

/// Счётчик «дней вместе» в уведомлениях. По умолчанию выключен.
///
/// **Android** — постоянная тихая плашка в шторке: канал с Importance.low и
/// silent, ongoing, чтобы не смахнуть случайно. Число пересчитывается при
/// включении тумблера, на старте приложения (rescheduleOnAppStart), при
/// возврате в него (refresh) и раз в сутки в 00:10 повторяющимся
/// zonedSchedule.
///
/// **iPhone** — ежедневное уведомление в 9 утра, и устроено оно иначе.
/// Постоянных уведомлений в iOS нет, фоновой доставки у нас нет тоже, а текст
/// уведомления записывается в момент планирования и сам не пересчитывается.
/// Одно повторяющееся уведомление поэтому каждый день показывало одно и то же
/// число (жалоба от 30 июля: «в приложении меняется, а в уведомлении всегда
/// 1349»). Вместо него планируется [_iosDaysAhead] отдельных уведомлений — на
/// каждый день своё, с числом, посчитанным на этот день. Пачка целиком
/// переписывается при каждом открытии приложения, так что запас не кончается;
/// а если приложение не открывать дольше трёх недель, уведомления замолчат до
/// следующего открытия — это лучше, чем врать числом.
class DaysTogetherNotificationService {
  DaysTogetherNotificationService._();
  static final DaysTogetherNotificationService instance =
      DaysTogetherNotificationService._();

  // Уникальный ID (не пересекается с 9001-9004 праздники, 9991 маскот, 8888 mood)
  static const int _notificationId = 9101;

  /// На сколько дней вперёд планируется пачка на iPhone. Слоты занимают
  /// id 9101…9121; лимит iOS — 64 отложенных уведомления на всё приложение,
  /// и часть их разбирают праздники, капсулы и маскот.
  static const int _iosDaysAhead = 21;

  /// Час ежедневного показа на iPhone. Ночные 00:10 Android-плашки здесь не
  /// годятся: на iOS это не тихая строчка в шторке, а баннер на экране.
  static const int _iosHour = 9;
  static const String _channelId = 'days_together_v1';
  static const String _channelName = 'Дни вместе';
  static const String _channelDesc =
      'Постоянный счётчик дней, проведённых вместе';

  static const String _keyEnabled = 'days_together_notif_enabled';
  static const String _keyStartMs = 'days_together_start_ms';
  static const String _keyIosLegacyCleared = 'days_together_ios_legacy_cleared';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Init ───────────────────────────────────────────────────────────────────

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

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.low, // тихо: без звука и без heads-up
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    if (Platform.isIOS || Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: false, sound: false);
    }

    _initialized = true;
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Текущее состояние тумблера (по умолчанию выключено).
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  /// Включает/выключает счётчик.
  /// [startDate] — дата начала отношений; если null, берётся ранее сохранённая.
  Future<void> setEnabled(bool value, {DateTime? startDate}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
    if (startDate != null) {
      await prefs.setInt(_keyStartMs, startDate.millisecondsSinceEpoch);
    }
    if (value) {
      await _refresh();
    } else {
      await _cancel();
    }
  }

  /// Вызывается из home_screen при появлении/смене даты начала.
  /// [startDate] == null → пара распалась, счётчик убираем.
  Future<void> onStartDateChanged(DateTime? startDate) async {
    final prefs = await SharedPreferences.getInstance();
    if (startDate == null) {
      await prefs.remove(_keyStartMs);
      await _cancel();
      return;
    }
    await prefs.setInt(_keyStartMs, startDate.millisecondsSinceEpoch);
    if (await isEnabled()) await _refresh();
  }

  /// Пересчёт расписания при старте приложения.
  Future<void> rescheduleOnAppStart() async {
    await _clearIosLegacyOnce();
    await _refresh();
  }

  /// Разовая уборка наследия старой схемы на iPhone.
  ///
  /// Раньше ставилось одно повторяющееся уведомление с числом, вписанным в
  /// текст навсегда. Снять его мог только `_cancel`, а `_refresh` при
  /// выключенном тумблере выходит первой же строкой — у того, кто успел
  /// выключить счётчик, оно приходило бы каждый день до переустановки
  /// приложения.
  Future<void> _clearIosLegacyOnce() async {
    if (!(Platform.isIOS || Platform.isMacOS)) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyIosLegacyCleared) ?? false) return;
    await init();
    await _cancelIosBatch();
    await prefs.setBool(_keyIosLegacyCleared, true);
  }

  /// Пересчёт при возврате в приложение (count мог измениться за полночь).
  Future<void> refresh() => _refresh();

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<DateTime?> _startDate() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyStartMs);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Сколько дней «вместе» на момент [when] — та же формула, что в профиле
  /// (`_calculateDaysTogether`): разница в полных сутках, минимум 0.
  int _daysAt(DateTime start, DateTime when) {
    final d = when.difference(start).inDays;
    return d < 0 ? 0 : d;
  }

  Future<void> _refresh() async {
    if (!await isEnabled()) return;
    final start = await _startDate();
    if (start == null) return;
    await init();

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Android 13+ требует явного разрешения POST_NOTIFICATIONS.
    // Общий сериализатор: не падаем на параллельном запросе (permissionRequestInProgress).
    await requestNotificationPermissionSafely(androidPlugin);

    if (Platform.isIOS || Platform.isMacOS) {
      // Постоянной плашки на iOS нет, показывать «прямо сейчас» нечего:
      // человек и так в приложении, где число видно крупно.
      await _scheduleIosBatch(start);
      return;
    }

    // 1) Показать прямо сейчас с актуальным числом.
    await _show(_daysAt(start, DateTime.now()));

    // 2) Запланировать ежесуточное обновление в 00:10.
    await _scheduleDailyRefresh(start);
  }

  /// Пачка ежедневных уведомлений на iPhone: на каждый день своё число.
  Future<void> _scheduleIosBatch(DateTime start) async {
    final s = LocaleService.current;
    final ticks = daysTogetherTicks(
      start: start,
      from: DateTime.now(),
      count: _iosDaysAhead,
      hour: _iosHour,
    );

    // Сначала снимаем прежнюю пачку: дату начала могли поправить, и старые
    // слоты показывали бы числа от другой даты.
    await _cancelIosBatch();

    for (var i = 0; i < ticks.length; i++) {
      final tick = ticks[i];
      try {
        await _plugin.zonedSchedule(
          id: _notificationId + i,
          title: s.daysTogetherNotifBody(tick.days),
          body: s.daysTogetherNotifTagline,
          scheduledDate: tz.TZDateTime.from(tick.at, tz.local),
          notificationDetails: _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (e) {
        debugPrint('DaysTogetherNotificationService._scheduleIosBatch($i): $e');
      }
    }
  }

  Future<void> _cancelIosBatch() async {
    for (var i = 0; i < _iosDaysAhead; i++) {
      try {
        await _plugin.cancel(id: _notificationId + i);
      } catch (e) {
        debugPrint('DaysTogetherNotificationService._cancelIosBatch($i): $e');
      }
    }
  }

  Future<void> _show(int days) async {
    final s = LocaleService.current;
    try {
      await _plugin.show(
        id: _notificationId,
        title: s.daysTogetherNotifBody(days),
        body: s.daysTogetherNotifTagline,
        notificationDetails: _details(),
      );
    } catch (e) {
      debugPrint('DaysTogetherNotificationService._show failed: $e');
    }
  }

  Future<void> _scheduleDailyRefresh(DateTime start) async {
    final s = LocaleService.current;
    try {
      final now = tz.TZDateTime.now(tz.local);
      var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, 0, 10);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      // Число на момент следующего срабатывания (по календарным суткам).
      final daysAtNext =
          _daysAt(start, DateTime(next.year, next.month, next.day));

      await _plugin.zonedSchedule(
        id: _notificationId,
        title: s.daysTogetherNotifBody(daysAtNext),
        body: s.daysTogetherNotifTagline,
        scheduledDate: next,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time, // повтор каждый день
      );
    } catch (e) {
      debugPrint(
          'DaysTogetherNotificationService._scheduleDailyRefresh failed: $e');
    }
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.low,
          priority: Priority.low,
          icon: '@drawable/ic_notification',
          ongoing: true, // не смахивается случайно
          autoCancel: false,
          onlyAlertOnce: true, // без повторного звука/вибро при обновлении
          showWhen: false,
          silent: true,
          playSound: false,
          enableVibration: false,
          channelShowBadge: false,
          category: AndroidNotificationCategory.status,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      );

  Future<void> _cancel() async {
    await init();
    if (Platform.isIOS || Platform.isMacOS) {
      await _cancelIosBatch();
      return;
    }
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('DaysTogetherNotificationService._cancel failed: $e');
    }
  }
}
