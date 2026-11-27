import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/push_slot.dart';

/// Обращение 25.11.2026 (Android, 1.44): «уведомления о сообщениях приходят
/// дважды». Сообщение партнёра доходит двумя путями: сокет приложения
/// поднимает своё уведомление (`PbPushService`), а сервер, не видя человека
/// на связи, шлёт пуш FCM, и его баннер рисует система. Система различает
/// уведомления по паре (метка, номер): у пуша это (вид события, 0), у своего
/// уведомления была метка null и номер от id записи, поэтому в шторке
/// вставали два одинаковых.
void main() {
  group('место уведомления в шторке', () {
    test('на Android совпадает с баннером пуша FCM: метка — вид события, номер 0', () {
      for (final thread in ['chat', 'mood', 'miss', 'memory', 'gift']) {
        final slot = pushSlot(thread: thread, ownId: 12345, android: true);
        expect(slot.tag, thread);
        expect(slot.id, 0);
      }
    });

    test('без вида события и на iPhone остаётся своё место', () {
      expect(pushSlot(thread: null, ownId: 77, android: true).id, 77);
      expect(pushSlot(thread: null, ownId: 77, android: true).tag, isNull);
      final ios = pushSlot(thread: 'chat', ownId: 77, android: false);
      expect(ios.id, 77);
      expect(ios.tag, isNull);
    });
  });

  test('каждое уведомление о партнёре несёт вид события, который шлёт сервер', () {
    // Виды, с которыми сервер зовёт релей FCM (поле tag). Новый вид пуша —
    // новая строка здесь и `thread:` у своего уведомления, иначе снова два.
    final server = File('pocketbase/hotpath/hotpath.py').readAsStringSync() +
        File('pocketbase/pb_hooks/push_apns.pb.js').readAsStringSync() +
        File('pocketbase/pb_hooks/gift_push.js').readAsStringSync();
    final app = File('lib/services/pb_push_service.dart').readAsStringSync();
    for (final thread in ['chat', 'mood', 'miss', 'memory', 'gift']) {
      expect(server, contains('"$thread"'), reason: 'сервер шлёт $thread');
      expect(app, contains("thread: '$thread'"),
          reason: 'своё уведомление «$thread» без метки встанет вторым');
    }
    // Подписки на события партнёра не зовут показ без метки.
    final subs = app.substring(app.indexOf('// 1) Чат'), app.indexOf('/// Тело уведомления по типу вайба'));
    final calls = RegExp(r'_notify\(').allMatches(subs).length;
    final tagged = RegExp(r"thread: '").allMatches(subs).length;
    expect(tagged, calls);
  });
}
