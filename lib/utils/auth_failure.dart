import 'dart:async';
import 'dart:io';

import 'package:pocketbase/pocketbase.dart';

/// Почему не удался вход или регистрация.
///
/// Экраны разбирали ошибку поиском подстрок в `e.toString()`, и всё, что не
/// попало в список, показывалось человеку как есть — с `tls_record.cc:127` и
/// прочими внутренностями. Разбор собран сюда, чтобы вход и регистрация
/// объясняли причину одинаково и по-человечески.
enum AuthFailure {
  /// Соединение ломают по дороге: в ответ на запрос пришёл не TLS. Так
  /// выглядит вмешательство провайдера — сервер при этом жив и отвечает всем
  /// остальным.
  blockedConnection,

  /// До сервера не дозвониться: сети нет или она отвалилась.
  noConnection,

  /// Ответа не дождались.
  timeout,

  /// Аккаунт с такой почтой уже есть.
  emailTaken,

  /// Неверная почта или пароль. PocketBase намеренно не различает их, чтобы по
  /// ответу нельзя было перебрать чужие адреса.
  badCredentials,

  /// Слишком много попыток подряд.
  tooManyAttempts,

  /// Сервер отвечает ошибкой на своей стороне.
  serverDown,

  /// Причина не опознана — только в этом случае показываем подробности.
  unknown;

  /// Разбирает исключение слоя данных.
  static AuthFailure of(Object error) {
    if (error is TimeoutException) return timeout;
    if (error is HandshakeException) return blockedConnection;
    if (error is SocketException) return noConnection;

    if (error is ClientException) {
      final original = error.originalError;
      if (original is HandshakeException) return blockedConnection;
      if (original is SocketException) return noConnection;
      if (original is TimeoutException) return timeout;

      final code = error.statusCode;
      if (code == 429) return tooManyAttempts;
      if (code >= 500) return serverDown;
      if (code == 400 || code == 403) {
        return _saysEmailTaken(error) ? emailTaken : badCredentials;
      }
      // statusCode 0 — до сервера не дошли вовсе, а тип обрыва не опознан.
      if (code == 0) return noConnection;
    }

    return unknown;
  }

  /// Дубль почты PocketBase отдаёт кодом поля, а не текстом сообщения: текст
  /// приходит на языке сервера и меняется от версии к версии.
  static bool _saysEmailTaken(ClientException e) =>
      e.response.toString().contains('validation_not_unique') ||
      e.toString().contains('validation_not_unique');
}
