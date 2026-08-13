// Бесконечный перевыпуск кода приглашения (13 августа 2026).
//
// Жалоба тестера и письмо в поддержку в один вечер: «код генерируется
// бесконечно», «приложение просит обновить код, дальше он обновляется без конца
// и не выдаёт новый», пара собраться не может. В базе к тому моменту лежало
// 60 076 кодов на 26 233 владельцев, у одного человека — 346.
//
// Причин было две, и обе снимаются здесь:
//   1. `generateInviteCode` сносил прежний код ДО того, как создать новый. На
//      тяжёлом сервере (в тот вечер запись висела по 30–50 секунд) все восемь
//      попыток создания падали — и человек оставался вовсе без кода.
//   2. Пустой ответ клали в поле кода. Экран, увидев пустоту, просил перевыпуск
//      заново — круг замыкался.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/connection.dart';

void main() {
  group('что остаётся на экране после перевыпуска', () {
    test('удачный перевыпуск показывает новый код', () {
      expect(
        Connection.codeAfterRegenerate(current: 'AB12CD', fresh: 'XY99ZZ'),
        'XY99ZZ',
      );
    });

    test('сервер не смог — на экране остаётся прежний код', () {
      expect(
        Connection.codeAfterRegenerate(current: 'AB12CD', fresh: ''),
        'AB12CD',
      );
    });

    test('кода не было и не появилось — поле остаётся пустым', () {
      expect(Connection.codeAfterRegenerate(current: '', fresh: ''), '');
    });

    test('первый код встаёт на пустое место', () {
      expect(Connection.codeAfterRegenerate(current: '', fresh: 'QQ11WW'), 'QQ11WW');
    });
  });

  test('прежний код сносится только после создания нового', () {
    final src = File('lib/services/pb_data_service.dart').readAsStringSync();
    final start = src.indexOf('Future<String> generateInviteCode(');
    expect(start, greaterThan(0), reason: 'метод переименовали — поправьте сторожа');
    final body = src.substring(start, start + 2600);

    final create = body.indexOf("collection('invite_codes').create(");
    final delete = body.indexOf('deleteInviteCode(oldCode)');
    expect(create, greaterThan(0), reason: 'создание кода не найдено');
    expect(delete, greaterThan(0), reason: 'удаление прежнего кода не найдено');
    expect(
      delete,
      greaterThan(create),
      reason: 'удаление прежнего кода обязано идти ПОСЛЕ успешного создания: '
          'иначе неудачная попытка оставляет человека без кода вовсе',
    );
  });
}
