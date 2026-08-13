import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pocketbase_service.dart';

/// Нужен ли фоновый сокет-сервис вместо пушей.
///
/// Свой foreground-сервис (`PushBackgroundService`) держал SSE-подписку, пока
/// приложение свёрнуто, и стоил строки «Togetherly на связи» в шторке у
/// каждого. С FCM сокет держит система, и сервис не нужен — но только там, где
/// пуши реально дойдут: на прошивках без сервисов Google их нет вовсе, а без
/// токена сервер не знает, куда слать. Остаться без уведомлений хуже, чем со
/// строкой в шторке, поэтому в обоих случаях возвращаемся к прежнему пути.
bool socketServiceNeeded({
  required bool hasGoogleServices,
  required bool hasToken,
}) =>
    !(hasGoogleServices && hasToken);

/// Токен устройства для пушей Google (Android).
///
/// Плагин `firebase_messaging` намеренно не подключён: на iOS он перехватывает
/// делегата APNs через swizzling, а там уже работает свой путь с ручным
/// токеном. Поэтому FCM живёт нативно (`FcmService.kt`), а сюда приходит через
/// канал `love_app/fcm`.
///
/// Токен уезжает в `users.fcm_token`, откуда его берёт серверный модуль
/// рассылки (`pb_hooks/apns_push.js`) — тот же, что шлёт на iPhone.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();
  factory FcmService() => instance;

  static const _channel = MethodChannel('love_app/fcm');

  bool _started = false;
  bool _hasServices = false;
  String? _token;

  String? get token => _token;

  /// Дойдут ли пуши до этого телефона.
  bool get ready => _hasServices && (_token ?? '').isNotEmpty;

  /// Спрашивает токен и держит его в профиле свежим.
  ///
  /// Звать после первого кадра: до `runApp` окна нет, а сюда приходят вызовы
  /// платформы. Ошибки глушим — пуши не стоят сорванного запуска.
  Future<void> start() async {
    if (_started || !Platform.isAndroid) return;
    _started = true;

    try {
      _hasServices = await _channel.invokeMethod<bool>('hasServices') ?? false;
      if (!_hasServices) {
        debugPrint('FcmService: сервисов Google нет — остаёмся на сокете');
        return;
      }
      final token = await _channel.invokeMethod<String>('getToken');
      await _remember(token);
    } catch (e) {
      debugPrint('FcmService: токен не получен — $e');
    }
  }

  Future<void> _remember(String? raw) async {
    final token = (raw ?? '').trim();
    if (token.isEmpty || token == _token) return;
    _token = token;
    await _saveToProfile(token);
  }

  /// Кладёт токен в свою запись `users`. Без сессии не пишем — запишем после
  /// входа ([syncAfterLogin]).
  Future<void> _saveToProfile(String token) async {
    final svc = PocketBaseService();
    final uid = svc.userId;
    if (uid == null || uid.isEmpty || !svc.isLoggedIn) return;
    try {
      await svc.pb.collection('users').update(uid, body: {'fcm_token': token});
      debugPrint('FcmService: токен устройства записан в профиль');
    } catch (e) {
      debugPrint('FcmService: токен не записался — $e');
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
