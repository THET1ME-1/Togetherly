import 'package:sentry_flutter/sentry_flutter.dart';

/// Как собиралась одна совместная лента: что грузила скрытая страница
/// площадки и сколько номеров роликов пришло.
///
/// «Собираем ленту…» висело без конца (чат, 19.10.2026, iPhone, TikTok), а
/// понять, на каком шаге встало, было не по чему: скрытая страница живёт на
/// телефоне, сервер её не видит, и лента не слала ничего. Теперь лента без
/// единого ролика за [limit] отдаёт отчёт, один раз за запуск ленты.
class ReelsWatch {
  ReelsWatch({required this.source, required this.started});

  /// Сколько ждём первых роликов, прежде чем считать ленту застрявшей. Сюда
  /// входит и проверка, закрыт ли TikTok (до 12 секунд), и загрузка страницы.
  static const Duration limit = Duration(seconds: 25);

  final String source;
  final DateTime started;

  /// Сколько раз скрытая страница догрузилась до конца.
  int pages = 0;
  String? lastHost;
  String? lastTitle;

  /// Последний отказ загрузки самой страницы: код и описание.
  String? lastError;

  /// Номеров пришло со страницы всего и сколько из них легло в запас.
  int heard = 0;
  int ids = 0;

  bool _sent = false;

  /// Отчёт о застрявшей ленте или null: ролики есть, рано или уже отправлен.
  Map<String, Object?>? check(
    DateTime now, {
    required bool proxyOn,
    required bool? blocked,
    String? proxyError,
  }) {
    if (_sent || ids > 0) return null;
    final ms = now.difference(started).inMilliseconds;
    if (ms < limit.inMilliseconds) return null;
    _sent = true;
    return {
      'source': source,
      'ms': ms,
      'pages': pages,
      'host': lastHost,
      'title': lastTitle,
      'error': ?lastError,
      'heard': heard,
      'ids': ids,
      'proxy_on': proxyOn,
      'blocked': blocked,
      'proxy_error': ?proxyError,
    };
  }
}

/// Отчёты совместной ленты в Bugsink.
class ReelsTelemetry {
  const ReelsTelemetry._();

  /// Лента не собрала ни одного ролика. Площадка, прокси и закрытость TikTok
  /// уходят тегами, чтобы события в панели группировались по причине.
  static void stalled(Map<String, Object?> report) {
    Sentry.captureMessage(
      'reels: лента не собралась',
      level: SentryLevel.warning,
      withScope: (s) {
        s.setTag('feature', 'reels');
        s.setTag('reels_source', '${report['source']}');
        s.setTag('reels_proxy', '${report['proxy_on']}');
        s.setTag('reels_blocked', '${report['blocked']}');
        s.setContexts('reels', report);
      },
    );
  }
}
