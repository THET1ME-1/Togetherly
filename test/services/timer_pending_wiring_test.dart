import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Связка неотправленных правок таймеров (обращение 358). Сервис таймеров
/// держится на одиночке-репозитории, поэтому подключение сверяем по исходнику.
void main() {
  final service = File('lib/services/timer_service.dart').readAsStringSync();
  final data = File('lib/services/pb_data_service.dart').readAsStringSync();

  String body(String src, String head) {
    final start = src.indexOf(head);
    expect(start, isNonNegative, reason: head);
    final next = src.indexOf('\n  Future<', start + head.length);
    return src.substring(start, next < 0 ? src.length : next);
  }

  test('правка и новый таймер не пишут на сервер весь свой список', () {
    // Старая копия списка на одном телефоне затирала свежую дату с другого.
    expect(body(service, 'Future<bool> updateTimer('), isNot(contains('_saveToFirestore')));
    expect(body(service, 'Future<void> addTimer('), isNot(contains('_saveToFirestore')));
  });

  test('правка и новый таймер ждут подтверждения сервера', () {
    expect(body(service, 'Future<bool> updateTimer('), contains('_sendTimer('));
    expect(body(service, 'Future<void> addTimer('), contains('_sendTimer('));
    expect(body(service, 'Future<bool> _sendTimer('), contains('_pending['));
  });

  test('обновление пары не откатывает неотправленную правку', () {
    expect(service, contains('mergeWithPending('));
    expect(service, contains('stillPending('));
  });

  test('сервер сам сводит флаг основного таймера', () {
    expect(body(data, 'Future<bool> upsertGroupTimer('), contains('upsertTimerJson('));
  });
}
