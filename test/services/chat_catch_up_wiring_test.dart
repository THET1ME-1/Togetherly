// TOG-17: открытый чат дотягивает сообщения, прошедшие мимо сокета.
//
// Само правило под тестами в catch_up_driver_test.dart. Здесь — что чат его
// включает: без флага поток снова видит только сокет, и сообщение партнёра
// появляется лишь после выхода из чата и повторного входа. Поломка тихая,
// ни одной ошибки в журнале.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/services/pb_realtime_service.dart').readAsStringSync();

  test('поток чата включает подхват пропущенного', () {
    final start = src.indexOf('Stream<List<RecordModel>> watchMessages(');
    expect(start, isNonNegative, reason: 'watchMessages не найден');
    final body = src.substring(start, src.indexOf(');', start));
    expect(body, contains('catchUp: true'));
  });

  test('подхват слушает переподключение, возврат приложения и живость канала', () {
    expect(src, contains('CatchUpDriver('));
    expect(src, contains('reconnected: CentrifugoService.instance.reconnected'));
    expect(src, contains('CentrifugoService.instance.isSubscribed(channel)'));
    expect(src, contains('onShow: () => visible.add(true)'));
    expect(src, contains('catchUpDriver?.dispose()'),
        reason: 'закрытый чат не должен дальше ходить на сервер');
  });
}
