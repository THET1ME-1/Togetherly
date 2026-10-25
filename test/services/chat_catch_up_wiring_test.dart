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

  // TOG-36: пуш о сообщении при открытом приложении сразу догоняет чат.
  group('пуш о сообщении догоняет открытый чат', () {
    final kotlinDir = 'android/app/src/main/kotlin/com/togetherly/love';

    test('чат просит догон по пушу своего вида', () {
      final start = src.indexOf('Stream<List<RecordModel>> watchMessages(');
      final body = src.substring(start, src.indexOf(');', start));
      expect(body, contains("catchUpPush: 'chat'"));
      expect(src, contains('PushArrivals.instance.of('));
    });

    test('Android отдаёт в Dart пуш, пришедший при открытом приложении', () {
      final fcm = File('$kotlinDir/FcmService.kt').readAsStringSync();
      expect(fcm, contains('PushArrivedBridge.arrived('));
      final activity = File('$kotlinDir/MainActivity.kt').readAsStringSync();
      expect(activity, contains('PushArrivedBridge.attach('));
      expect(activity, contains('PushArrivedBridge.detach()'));
    });

    test('iPhone отдаёт в Dart пуш из willPresent', () {
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      final start = swift.indexOf('willPresent notification: UNNotification');
      expect(start, isNonNegative);
      final body = swift.substring(start, swift.indexOf('\n  }\n', start));
      expect(body, contains('pushArrived('));
    });

    test('имя канала одно в Dart, Kotlin и Swift', () {
      final dart = File('lib/services/push_arrivals.dart').readAsStringSync();
      final kotlin = File('$kotlinDir/PushArrivedBridge.kt').readAsStringSync();
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      const name = 'love_app/push_arrived';
      expect(dart, contains("'$name'"));
      expect(kotlin, contains('"$name"'));
      expect(swift, contains('"$name"'));
    });
  });
}
