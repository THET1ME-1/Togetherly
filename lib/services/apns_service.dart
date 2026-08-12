import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pocketbase_service.dart';

/// Токен устройства для пушей Apple.
///
/// Уведомления рисует само приложение, слушая realtime PocketBase. Пока процесс
/// жив — всё приходит, но iOS выгружает его быстро, сокет умирает вместе с ним,
/// и о сообщении или «скучаю» человек не узнаёт. Так и появилась главная жалоба
/// после выхода в App Store: «уведы с закрытым приложением не ворк».
///
/// Лечится пушем от Apple. Приложение отдаёт токен устройства в свой профиль
/// (`users.apns_token`), а серверный хук `push_apns.pb.js` шлёт по нему пуш —
/// но только тем, кто сейчас не на связи, иначе баннер придёт дважды.
///
/// `apns_sandbox` отличает сборки из Xcode: у них токен из песочницы, и
/// production-шлюз Apple такой токен не принимает.
class ApnsService {
  ApnsService._();
  static final ApnsService instance = ApnsService._();
  factory ApnsService() => instance;

  static const _channel = MethodChannel('love_app/apns');

  bool _started = false;
  String? _token;

  String? get token => _token;

  /// Просит систему выдать токен и держит его в профиле свежим.
  ///
  /// Звать после первого кадра: до `runApp` сцены нет, а нам нужен живой канал.
  /// Ошибки глушим — пуши не стоят сорванного запуска.
  Future<void> start() async {
    if (_started || !Platform.isIOS) return;
    _started = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'token') {
        await _remember(call.arguments as String?);
      }
      return null;
    });

    try {
      // Токен мог приехать до того, как Dart попросил: нативная сторона держит
      // последний и отдаёт его прямо в ответе.
      final ready = await _channel.invokeMethod<String>('register');
      await _remember(ready);
    } catch (e) {
      debugPrint('ApnsService: регистрация не удалась — $e');
    }
  }

  /// Кладёт токен в профиль, если он изменился.
  Future<void> _remember(String? raw) async {
    final token = (raw ?? '').trim();
    if (token.isEmpty || token == _token) return;
    _token = token;
    await _saveToProfile(token);
  }

  /// Записывает токен в свою запись `users`. Без сессии не пишем — сохраним при
  /// следующем запуске, когда вход уже будет.
  Future<void> _saveToProfile(String token) async {
    final svc = PocketBaseService();
    final uid = svc.userId;
    if (uid == null || uid.isEmpty || !svc.isLoggedIn) return;
    try {
      await svc.pb.collection('users').update(uid, body: {
        'apns_token': token,
        'apns_sandbox': kDebugMode,
      });
      debugPrint('ApnsService: токен устройства записан в профиль');
    } catch (e) {
      debugPrint('ApnsService: токен не записался — $e');
    }
  }

  /// Повторная попытка после входа: на первом запуске токен приезжает раньше,
  /// чем человек успевает войти, и записать его тогда некуда.
  Future<void> syncAfterLogin() async {
    final t = _token;
    if (t == null || t.isEmpty) return;
    await _saveToProfile(t);
  }
}
