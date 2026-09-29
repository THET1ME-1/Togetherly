import 'package:sentry_flutter/sentry_flutter.dart';

/// Телеметрия сундука в Bugsink (обращение 211, 29.09.2026).
///
/// Человек досмотрел пять роликов, а сундук открылся один раз, и понять, на
/// каком шаге всё вставало, было не по чему: удачные запросы сервер не пишет,
/// а приложение молчало. Теперь каждый шаг от ролика до приза оседает крошкой
/// с номером открытия, а сбой уходит событием со всей цепочкой. Тот же номер
/// сервер пишет в журнал (`chest ad`, `chest open`) — их можно сопоставить.
class ChestTelemetry {
  const ChestTelemetry._();

  /// Шаг открытия. Попадает в отчёт о любом следующем сбое.
  static void step(String openId, String step, {Map<String, Object?>? data}) {
    Sentry.addBreadcrumb(Breadcrumb(
      category: 'chest',
      message: step,
      level: SentryLevel.info,
      data: {'open_id': openId, ...?data},
    ));
  }

  /// Сундук не открылся или открывался слишком долго. Код уходит тегом,
  /// чтобы события в панели группировались по причине.
  static void failure(String openId, String step, String code, {Map<String, Object?>? data}) {
    Sentry.captureMessage(
      'chest: не открылся — $code',
      level: SentryLevel.warning,
      withScope: (s) {
        s.setTag('feature', 'chest');
        s.setTag('open_id', openId);
        s.setTag('chest_step', step);
        s.setTag('error_code', code);
        if (data != null) s.setContexts('chest', data);
      },
    );
  }
}
