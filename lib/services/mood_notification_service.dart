import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Сервис постоянного уведомления с настроением на Android.
///
/// На Android нет API виджетов экрана блокировки (убрали в Android 5+),
/// поэтому лучший вариант — ongoing-уведомление (permanent notification),
/// которое всегда видно в шторке уведомлений прямо с экрана блокировки
/// без разблокировки телефона.
class MoodNotificationService {
  MoodNotificationService._();
  static final MoodNotificationService instance = MoodNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const int _kNotificationId = 8888;
  // v2: importance bumped to default so the notification appears on the lock
  // screen (low-importance notifications are filtered out on most Android skins)
  static const String _kChannelId = 'mood_lock_screen_v2';
  static const String _kChannelName = 'Настроение';

  // ─────────────────────────────────────────────────────────────────────────
  //  INIT
  // ─────────────────────────────────────────────────────────────────────────

  /// Инициализация (вызывать один раз при старте приложения).
  Future<void> init() async {
    if (_initialized || !Platform.isAndroid) return;
    try {
      const androidSettings = AndroidInitializationSettings(
        '@drawable/ic_notification',
      );
      const initSettings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(settings: initSettings);

      // Default importance is required for the notification to appear on the
      // lock screen; low-importance is silently filtered by most Android skins.
      // Sound and vibration are explicitly disabled so it stays unobtrusive.
      const channel = AndroidNotificationChannel(
        _kChannelId,
        _kChannelName,
        description: 'Настроение на экране блокировки',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      _initialized = true;
      debugPrint('MoodNotificationService: initialized');
    } catch (e) {
      debugPrint('MoodNotificationService.init failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  SHOW / HIDE
  // ─────────────────────────────────────────────────────────────────────────

  /// Показать / обновить постоянное уведомление с настроением.
  ///
  /// [myMood]      — моё настроение (текст), например «Счастлив»
  /// [myName]      — моё имя
  /// [partnerMood] — настроение партнёра
  /// [partnerName] — имя партнёра
  Future<void> show({
    required String myMood,
    required String myName,
    String partnerMood = '',
    String partnerName = '',
  }) async {
    if (!Platform.isAndroid) return;
    await init();

    final title = _buildTitle(myName, myMood);
    final body = _buildBody(partnerName, partnerMood);

    final androidDetails = AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: 'Настроение на экране блокировки',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: '@drawable/ic_notification',
      color: const Color(0xFFEC4899),
      // PUBLIC — контент виден без разблокировки
      visibility: NotificationVisibility.public,
      channelShowBadge: false,
      playSound: false,
      enableVibration: false,
      silent: true,
    );

    await _plugin.show(
      id: _kNotificationId,
      title: title,
      body: body.isNotEmpty ? body : null,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
    debugPrint('MoodNotificationService: shown — $title | $body');
  }

  /// Скрыть постоянное уведомление.
  Future<void> hide() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.cancel(id: _kNotificationId);
      debugPrint('MoodNotificationService: hidden');
    } catch (e) {
      debugPrint('MoodNotificationService.hide failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  String _buildTitle(String name, String mood) {
    if (mood.isEmpty) return '😶 Настроение не задано';
    final emoji = _moodToEmoji(mood);
    if (name.isNotEmpty) return '$emoji $name: $mood';
    return '$emoji Моё настроение: $mood';
  }

  String _buildBody(String partnerName, String partnerMood) {
    if (partnerMood.isEmpty) return '';
    final emoji = _moodToEmoji(partnerMood);
    if (partnerName.isNotEmpty) return '$emoji $partnerName: $partnerMood';
    return '$emoji Партнёр: $partnerMood';
  }

  /// Грубое соответствие текстового ярлыка → emoji для уведомления.
  String _moodToEmoji(String label) {
    final l = label.toLowerCase();
    if (l.contains('сча') || l.contains('happ')) return '😊';
    if (l.contains('груст') || l.contains('sad')) return '😢';
    if (l.contains('злост') || l.contains('angry') || l.contains('rage')) {
      return '😠';
    }
    if (l.contains('влюб') || l.contains('love') || l.contains('star')) {
      return '🥰';
    }
    if (l.contains('устал') || l.contains('tired') || l.contains('dead')) {
      return '😵';
    }
    if (l.contains('весел') || l.contains('wink')) return '😜';
    if (l.contains('спок') || l.contains('cool')) return '😎';
    if (l.contains('плач') || l.contains('cry')) return '😭';
    if (l.contains('вкусн') || l.contains('yummy')) return '😋';
    return '😶';
  }
}
