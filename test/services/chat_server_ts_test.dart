import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож порядка сообщений в чате.
///
/// Порядок держится на `ts`, а ставит его телефон отправителя. Когда часы врут
/// больше чем на две минуты, сервер записывает своё время (`время_сообщения` в
/// hotpath.py) — и на этом расхождение начинается: у отправителя в кэше остаётся
/// его собственное, кривое. Ответ сервера код выбрасывал (upsert отдавал только
/// «получилось/нет»), а живую дельту про свою же запись поток отбрасывает, пока
/// она числится в очереди. Пока человек не перезапустит приложение, сообщения
/// партнёра стоят выше его собственных.
///
/// Жалоба: «сообщения "ответветчика" смещаются вверх сообщений пользователя, но
/// после перезагрузки приложения встают на место» (обращение №133, 06.09.2026).
void main() {
  String read(String path) => File(path).readAsStringSync();

  final data = read('lib/services/pb_data_service.dart');
  final hotpath = read('pocketbase/hotpath/hotpath.py');

  test('сервер по-прежнему вправе переписать время сообщения', () {
    expect(hotpath.contains('body["ts"] = время_сообщения('), isTrue,
        reason: 'Если правило убрали, сторож ниже сторожит пустоту');
  });

  test('отправка сообщения возвращает серверную запись', () {
    expect(data.contains('Future<RecordModel?> chatSendRecord('), isTrue,
        reason: 'Без записи от сервера исправленное время некуда взять');
  });

  test('серверное время сразу ложится в кэш', () {
    expect(data.contains("LocalStore.instance.upsert('chat_messages'"), isTrue,
        reason: 'Иначе порядок исправит только перезапуск приложения');
  });

  test('очередь чата идёт через этот же путь', () {
    final outbox = read('lib/services/offline/outbox_service.dart');
    expect(outbox.contains('data.chatSend('), isTrue,
        reason: 'Сообщения уходят очередью — правка мимо неё ничего не меняет');
    final send = data.substring(data.indexOf('Future<bool> chatSend('));
    expect(send.substring(0, 600).contains('chatSendRecord('), isTrue,
        reason: 'chatSend обязан спрашивать сервер, а не только «получилось ли»');
  });
}
