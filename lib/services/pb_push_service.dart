import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_service.dart';

/// Пуш-уведомления БЕЗ Firebase (миграция Firebase→PB, Этап 6, слой Пуш).
///
/// Заменяет связку «event-документ → Cloud Function → FCM → клиент». Теперь:
/// партнёр пишет в PB (chat_messages / widget_data-настроение / miss_you) →
/// SSE-событие приходит подписчику → приложение поднимает ЛОКАЛЬНОЕ уведомление.
/// Ноль FCM/Google. Для доставки в фоне сервис крутится в Android
/// foreground-сервисе (держит SSE-сокет живым) — см. cutover-интеграцию.
///
/// Тексты уведомлений зеркалят прежние Cloud Functions (onMissYouEvent/
/// onWidgetDataEvent/onChatMessageEvent).
class PbPushService {
  PbPushService._();
  static final PbPushService instance = PbPushService._();
  factory PbPushService() => instance;

  PocketBase get _pb => PocketBaseService().pb;

  final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();
  static const String _channelId = 'partner_notifications';
  static const String _channelName = 'Уведомления от партнёра';

  bool _inited = false;
  final List<UnsubscribeFunc> _subs = [];
  // дедуп: последний показанный счётчик «скучаю» и настроение партнёра
  int? _lastMissCount;
  String? _lastMood;

  /// Инициализация плагина локальных уведомлений + канал + разрешение (А13+).
  Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const ios = DarwinInitializationSettings();
    await _ln.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    final androidImpl = _ln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Сообщения, настроение и «скучаю» от партнёра',
        importance: Importance.high,
      ),
    );
    await androidImpl?.requestNotificationsPermission();
    _inited = true;
  }

  /// Настройки уведомлений текущего юзера (его профиль решает, что показывать).
  bool _pref(String col) {
    final v = PocketBaseService().currentUser?.data[col];
    return v is bool ? v : true; // по умолчанию включено
  }

  /// Запускает подписки на события партнёра в группе. [partnerUid] — чей
  /// активности уведомляем (только не свои).
  Future<void> start({
    required String groupId,
    required String myUid,
    required String partnerUid,
    String partnerName = 'Партнёр',
  }) async {
    if (groupId.isEmpty) return;
    await init();
    await stop();
    final gf = _pb.filter('group_id = {:g}', {'g': groupId});

    // 1) Чат
    _subs.add(await _pb.collection('chat_messages').subscribe('*', (e) {
      if (e.action != 'create') return;
      final r = e.record;
      if (r == null || r.data['user_uid'] != partnerUid) return;
      if (r.data['deleted'] == true || !_pref('notif_chat')) return;
      final name = (r.data['user_name'] ?? partnerName).toString();
      final text = (r.data['text'] ?? '').toString();
      _notify(r.id.hashCode, name, text.isEmpty ? '✉️' : text);
    }, filter: gf));

    // 2) Настроение (widget_data партнёра)
    _subs.add(await _pb.collection('widget_data').subscribe('*', (e) {
      final r = e.record;
      if (r == null || r.data['user_uid'] != partnerUid) return;
      final mood = (r.data['mood_label'] ?? '').toString();
      if (mood.isEmpty || mood == _lastMood) return; // дедуп по изменению
      _lastMood = mood;
      if (!_pref('notif_mood')) return;
      final name = (r.data['display_name'] ?? partnerName).toString();
      _notify(('mood$partnerUid').hashCode, name, 'Настроение: $mood');
    }, filter: gf));

    // 3) «Скучаю» (miss_you партнёра)
    _subs.add(await _pb.collection('miss_you').subscribe('*', (e) {
      final r = e.record;
      if (r == null || r.data['user_uid'] != partnerUid) return;
      final cnt = (r.data['count'] as num?)?.toInt() ?? 0;
      if (_lastMissCount != null && cnt <= _lastMissCount!) return; // только рост
      _lastMissCount = cnt;
      final vibe = (r.data['last_vibe'] ?? 'miss_you').toString();
      final custom = (r.data['last_vibe_text'] ?? '').toString();
      // custom доставляется всегда; остальное — по настройке notif_miss_you
      if (vibe != 'custom' && !_pref('notif_miss_you')) return;
      _notify(('miss$partnerUid$cnt').hashCode, partnerName, _vibeBody(vibe, custom));
    }, filter: gf));

    debugPrint('PbPush: подписки запущены (group=$groupId, partner=$partnerUid)');
  }

  /// Тело уведомления по типу вайба (зеркало Cloud Functions buildVibePayload).
  String _vibeBody(String vibe, String text) {
    switch (vibe) {
      case 'thinking_of_you':
        return 'Думает о тебе 💭';
      case 'want_hug':
        return 'Хочет обнять тебя 🤗';
      case 'custom':
        return text.isNotEmpty ? text : '✉️';
      default:
        return 'Думает о вас и вспоминает 💭';
    }
  }

  Future<void> _notify(int id, String title, String body) async {
    await _ln.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Сообщения, настроение и «скучаю» от партнёра',
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
    );
  }

  Future<void> stop() async {
    for (final u in _subs) {
      try {
        await u();
      } catch (_) {}
    }
    _subs.clear();
    _lastMissCount = null;
    _lastMood = null;
  }
}
