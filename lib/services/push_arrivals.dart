import 'dart:async';

import 'package:flutter/services.dart';

/// Пуши, пришедшие, пока приложение на экране (TOG-36).
///
/// Сервер шлёт пуш только тем, кого не видит на связи. Если он пришёл при
/// открытом приложении, значит, сокет Centrifugo умер молча, и открытый чат
/// ждёт его зря: приложение замечает такое через 35 секунд, а уведомление
/// уже видно («сообщение в чате появляется не сразу, а в уведомлении уже
/// видно», отзыв в Google Play 23.10.2026).
///
/// Вид пуша (`kind`: chat, memory, mood…) приносит нативная часть каналом
/// [channelName]: на Android `PushArrivedBridge` из
/// `FcmService.onMessageReceived`, на iPhone `AppDelegate` из `willPresent`.
class PushArrivals {
  PushArrivals._();
  static final PushArrivals instance = PushArrivals._();

  static const channelName = 'love_app/push_arrived';
  static const _channel = MethodChannel(channelName);

  final _kinds = StreamController<String>.broadcast();
  bool _wired = false;

  /// Пуши вида [kind]. Канал подключается при первом обращении: раньше
  /// слушать некому, а пропущенный пуш догонит возврат в приложение.
  Stream<void> of(String kind) {
    _wire();
    return _kinds.stream.where((k) => k == kind);
  }

  void _wire() {
    if (_wired) return;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'arrived') return null;
        final kind = call.arguments;
        if (kind is String && kind.isNotEmpty) _kinds.add(kind);
        return null;
      });
      _wired = true;
    } catch (_) {
      // Без привязки Flutter (чистый тест, фоновый изолят) моста нет, и
      // пушей сюда тоже не будет.
    }
  }
}
