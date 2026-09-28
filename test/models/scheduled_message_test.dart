import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/scheduled_message.dart';

void main() {
  test('придержано, пока срок впереди', () {
    final now = DateTime(2026, 9, 28, 22);
    expect(isHeld(now.add(const Duration(hours: 1)).millisecondsSinceEpoch, now: now), isTrue);
    expect(isHeld(0, now: now), isFalse);
    expect(isHeld(null, now: now), isFalse);
  });

  test('любая дата и время впереди, прошедшее — нет', () {
    final now = DateTime(2026, 9, 28, 22, 30);
    expect(scheduledMoment(DateTime(2027, 3, 8), 9, 0, now: now), DateTime(2027, 3, 8, 9));
    expect(scheduledMoment(DateTime(2026, 9, 28), 23, 0, now: now), DateTime(2026, 9, 28, 23));
    expect(scheduledMoment(DateTime(2026, 9, 28), 22, 0, now: now), isNull);
  });

  test('отложенное уходит на сервер полем deliver_at, а придержанное видно автору', () {
    // Сторож связки: поле в теле, в кэше и в модели, иначе сервер его не узнает.
    final body = File('lib/services/pb_data_service.dart').readAsStringSync();
    expect(body, contains("'deliver_at': msg['deliverAt']"));
    final chat = File('lib/services/chat_service.dart').readAsStringSync();
    expect(chat, contains("'deliver_at': ?deliverAt"));
    final model = File('lib/models/chat_msg.dart').readAsStringSync();
    expect(model, contains("deliverAt: nzInt(m['deliver_at'])"));
    final hp = File('pocketbase/hotpath/hotpath.py').readAsStringSync();
    expect(hp, contains('"deliver_at": "num"'));
    expect(hp, contains('_deliver_worker'));
  });
}
