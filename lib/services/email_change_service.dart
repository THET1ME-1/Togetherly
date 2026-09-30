import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import 'locale_service.dart';
import 'pocketbase_service.dart';

/// Смена почты аккаунта кодом из письма (хук pb_hooks/email_change.pb.js).
///
/// «У меня не та почта» правили руками через суперюзера. Штатная смена
/// PocketBase просит пароль, а у вошедших через Google и Apple его нет,
/// поэтому свой путь: код из шести цифр на новый адрес и ввод прямо в
/// приложении.

/// Почему не вышло. Приходит полем `code` в ответе сервера.
enum EmailChangeError {
  invalid,
  same,
  taken,
  wait,
  limit,
  expired,
  wrong,
  tries,
  mail,
  network,
}

class EmailChangeResult {
  const EmailChangeResult.ok({this.email = '', this.token = ''})
      : error = null,
        retryIn = 0;
  const EmailChangeResult.failed(EmailChangeError this.error, {this.retryIn = 0})
      : email = '',
        token = '';

  final EmailChangeError? error;

  /// Через сколько секунд можно прислать код ещё раз (для `wait`).
  final int retryIn;

  /// Новая почта и свежий токен входа — после подтверждения.
  final String email;
  final String token;

  bool get ok => error == null;
}

/// Разбор ответа сервера. Отдельно от сети, чтобы проверять тестом.
@visibleForTesting
EmailChangeResult parseEmailChange(int status, Map<String, dynamic>? body) {
  if (status >= 200 && status < 300 && body?['ok'] == true) {
    return EmailChangeResult.ok(
      email: body?['email'] as String? ?? '',
      token: body?['token'] as String? ?? '',
    );
  }
  final code = body?['code'] as String?;
  final error = EmailChangeError.values.firstWhere(
    (e) => e.name == code,
    orElse: () => EmailChangeError.network,
  );
  final retry = body?['retryIn'];
  return EmailChangeResult.failed(error,
      retryIn: retry is num ? retry.toInt() : 0);
}

class EmailChangeService {
  /// Открыт для теста: лист проверяется с подменённым сервисом.
  EmailChangeService();
  static final EmailChangeService instance = EmailChangeService();

  PocketBase get _pb => PocketBaseService().pb;

  Future<EmailChangeResult> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await _pb
          .send(path, method: 'POST', body: body)
          .timeout(const Duration(seconds: 25));
      return parseEmailChange(
          200, res is Map ? Map<String, dynamic>.from(res) : null);
    } on ClientException catch (e) {
      return parseEmailChange(
          e.statusCode, e.response.isEmpty ? null : Map<String, dynamic>.from(e.response));
    } catch (_) {
      return const EmailChangeResult.failed(EmailChangeError.network);
    }
  }

  /// Прислать код на новый адрес. Письмо идёт на языке приложения.
  Future<EmailChangeResult> requestCode(String email) =>
      _post('/api/account/email-change/request', {
        'email': email.trim(),
        'lang': LocaleService.instance.language.code,
      });

  /// Подтвердить код. Сервер меняет почту и выдаёт новый токен: смена почты
  /// обнуляет прежние, и без него человека выкинуло бы из приложения.
  Future<EmailChangeResult> confirm(String email, String code) async {
    final res = await _post('/api/account/email-change/confirm', {
      'email': email.trim(),
      'code': code.trim(),
    });
    if (!res.ok || res.token.isEmpty) return res;
    _pb.authStore.save(res.token, _pb.authStore.record);
    try {
      await _pb.collection('users').authRefresh();
    } catch (e) {
      // Токен уже новый и рабочий, запись освежится при следующем заходе.
      debugPrint('email-change: authRefresh $e');
    }
    return res;
  }
}
