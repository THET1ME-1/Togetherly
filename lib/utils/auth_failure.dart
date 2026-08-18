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

  /// Страница провайдера не открылась. Вход через Apple и Google идёт через
  /// встроенный браузер, и он иногда возвращает провал загрузки — сервер тут не
  /// при чём, до него дело не доходит (за сутки 59 таких обрывов против 31
  /// удачного входа, а в журнале сервера при этом одна ошибка). Человек видел
  /// вместо объяснения строку `PlatformException(Error, Error while launching
  /// https://appleid.apple.com/auth/authorize?client_id=…`.
  providerPageFailed,

  /// Сервер не дозвонился до Google или Apple. Обмен кода на профиль идёт с
  /// нашей машины, и когда связь до `googleapis.com` проседает, PocketBase
  /// отвечает 400 с текстом вида `Get "…/userinfo": context deadline exceeded`.
  /// Пока это считалось отказом по паролю, человек, вошедший через Google,
  /// читал «Неверная почта или пароль» и ждал ответа десятки секунд
  /// (жалоба 18.08.2026).
  providerUnreachable,

  /// Причина не опознана — только в этом случае показываем подробности.
  unknown;

  /// Разбирает исключение слоя данных.
  static AuthFailure of(Object error) {
    if (error is TimeoutException) return timeout;
    if (_isProviderPageFailure(error)) return providerPageFailed;
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
        if (_saysEmailTaken(error)) return emailTaken;
        if (_saysProviderUnreachable(error)) return providerUnreachable;
        return badCredentials;
      }
      // statusCode 0 — до сервера не дошли вовсе, а тип обрыва не опознан.
      if (code == 0) return noConnection;
    }

    return unknown;
  }

  /// Провал открытия страницы провайдера. Приходит от url_launcher: встроенный
  /// браузер сообщил, что страница не загрузилась, или контроллер для показа не
  /// нашёлся. Тип не импортируем — иначе слой данных потянет за собой Flutter.
  static bool _isProviderPageFailure(Object error) {
    final text = error.toString();
    if (!text.startsWith('PlatformException')) return false;
    return text.contains('Error while launching') ||
        text.contains('no view controller present');
  }

  /// Сбой похода сервера к провайдеру. Go пишет такие ошибки одинаково —
  /// `Get "<адрес>": <причина>`, — поэтому смотрим и на адрес провайдера, и на
  /// характерные причины обрыва.
  static bool _saysProviderUnreachable(ClientException e) {
    final text = '${e.response} ${e}'.toLowerCase();
    final aboutProvider = text.contains('googleapis.com') ||
        text.contains('accounts.google.com') ||
        text.contains('appleid.apple.com') ||
        text.contains('oauth2');
    if (!aboutProvider) return false;
    return text.contains('context deadline exceeded') ||
        text.contains('context canceled') ||
        text.contains('timeout') ||
        text.contains('no such host') ||
        text.contains('connection refused') ||
        text.contains('eof');
  }

  /// Дубль почты PocketBase отдаёт кодом поля, а не текстом сообщения: текст
  /// приходит на языке сервера и меняется от версии к версии.
  static bool _saysEmailTaken(ClientException e) =>
      e.response.toString().contains('validation_not_unique') ||
      e.toString().contains('validation_not_unique');
}
