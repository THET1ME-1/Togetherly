import 'package:pocketbase/pocketbase.dart' show ClientException;

/// Сброс пароля через партнёра (05.11.2026): человек на новом телефоне просит
/// код, партнёр видит его у себя в приложении. Сервер —
/// `pb_hooks/partner_reset.pb.js`.

/// Код по тройкам: «482 913» читается вслух без ошибок.
String formatResetCode(String code) =>
    code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

/// Запрос кода, который видит партнёр (`GET /api/auth/partner-reset/pending`).
class PendingReset {
  const PendingReset({
    required this.uid,
    required this.name,
    required this.female,
    required this.code,
    required this.at,
    required this.expiresAt,
  });

  /// null — запроса нет или ответ кривой.
  static PendingReset? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final code = json['code'];
    if (code is! String || !RegExp(r'^\d{6}$').hasMatch(code)) return null;
    DateTime time(Object? v) => DateTime.fromMillisecondsSinceEpoch(
      v is num ? v.toInt() : 0,
      isUtc: true,
    );
    return PendingReset(
      uid: json['uid'] is String ? json['uid'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      female: json['gender'] == 'female',
      code: code,
      at: time(json['at']),
      expiresAt: time(json['expiresAt']),
    );
  }

  final String uid;
  final String name;
  final bool female;
  final String code;
  final DateTime at;
  final DateTime expiresAt;

  /// Сколько коду осталось жить.
  Duration left(DateTime now) {
    final d = expiresAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

/// Пропуск после верного кода (`POST /api/auth/partner-reset/verify`).
class PartnerResetTicket {
  const PartnerResetTicket({
    required this.ticket,
    required this.name,
    required this.partnerName,
    required this.partnerFemale,
  });

  factory PartnerResetTicket.fromJson(Map<String, dynamic> json) =>
      PartnerResetTicket(
        ticket: json['ticket'] is String ? json['ticket'] as String : '',
        name: json['name'] is String ? json['name'] as String : '',
        partnerName: json['partnerName'] is String
            ? json['partnerName'] as String
            : '',
        partnerFemale: json['partnerGender'] == 'female',
      );

  final String ticket;
  final String name;
  final String partnerName;
  final bool partnerFemale;
}

/// Почему сервер отказал. Коды ответа — поле `code` в теле.
enum PartnerResetFailure {
  /// Код не подошёл, попытки ещё есть.
  wrong,

  /// Код истёк.
  expired,

  /// Промахов слишком много, код погашен.
  locked,

  /// Запроса нет: погашен партнёром или сервер перезапускался.
  none,

  /// Код уже у партнёра, новый — через две минуты.
  gap,

  /// Лимит запросов за сутки.
  day,

  /// Слишком много запросов с этого адреса.
  ip,

  /// Пароль короче восьми символов.
  short,

  /// Пароль длиннее 71 символа.
  long,

  /// До сервера не дошли.
  network,

  unknown,
}

PartnerResetFailure partnerResetFailureOf(Object e) {
  if (e is! ClientException) return PartnerResetFailure.unknown;
  if (e.statusCode == 0) return PartnerResetFailure.network;
  final code = e.response['code'];
  for (final f in PartnerResetFailure.values) {
    if (f.name == code) return f;
  }
  return PartnerResetFailure.unknown;
}

/// Сколько попыток осталось после промаха.
int triesLeftOf(Object e) {
  if (e is! ClientException) return 0;
  final left = e.response['left'];
  return left is num ? left.toInt() : 0;
}
