import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Уведомление на iPhone с выключенными уведомлениями.
///
/// Bugsink 23.10.2026, версия 1.38.0: «PlatformException(Error 2003,
/// Repository could not save notification. Source is not authorized.)» из
/// `PbPushService._notify`, 19 человек и 436 событий за сутки. Человек
/// выключил уведомления — это его выбор, а не сбой: показ не должен
/// выпускать исключение наружу и засорять отчёты.
void main() {
  test('показ уведомления глотает отказ платформы', () {
    final src = File('lib/services/pb_push_service.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _notify(');
    expect(start, isNot(-1));
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    final show = body.indexOf('_ln.show(');
    final tryAt = body.indexOf('try {');
    expect(tryAt, isNot(-1));
    expect(tryAt < show, isTrue, reason: '_ln.show должен стоять внутри try');
    expect(body, contains('on PlatformException'));
  });
}
