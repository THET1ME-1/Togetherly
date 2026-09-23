// Код на экране есть, а на сервере его нет (23 сентября 2026).
//
// У человека на экране подключения висел код TPNQGP. Партнёр ввёл его 27 раз
// за 8 минут, и каждый раз сервер отвечал «кода нет ни в invite_codes, ни в
// claim_token». С 20 сентября так же вели себя минимум 15 кодов. Попытки того
// же человека принять чужой живой код до сервера не доходили вовсе: сессия у
// него умерла (auth-refresh отвечал 401, и приложение вышло из аккаунта), а
// экран продолжал рисовать код из памяти телефона как настоящий.
//
// Цепочка до правки:
//   * `Connection.ensureInviteCodeIsReal` без сессии молча выходил, сверки не
//     было вовсе;
//   * при протухшем токене сверка шла гостем, сервер отдавал пустой список, и
//     код считался чужим, но перевыпуск без сессии не проходил, а
//     `codeAfterRegenerate` возвращал на экран прежний, уже мёртвый код;
//   * экран показывал любой непустой `inviteCode`, подтверждён он или нет.
//
// Правило теперь такое: код раздаётся только тот, что сервер выдал или
// подтвердил в этом запуске и за этим владельцем. Без сессии экран так и
// говорит, что связи с аккаунтом нет.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/connection.dart';
import 'package:love_app/models/invite_code_state.dart';

void main() {
  group('что экран вправе показать на месте кода', () {
    test('без сессии код не показывается, даже если он лежит в памяти', () {
      expect(
        inviteCodeStateOf(code: 'TPNQGP', signedIn: false, confirmed: false),
        InviteCodeState.sessionLost,
      );
      expect(
        inviteCodeStateOf(code: 'TPNQGP', signedIn: false, confirmed: true),
        InviteCodeState.sessionLost,
        reason: 'без сессии сервер нас не узнаёт: ни принять чужой код, ни '
            'проверить свой',
      );
    });

    test('код, который сервер не подтвердил, не выдаётся за рабочий', () {
      expect(
        inviteCodeStateOf(code: 'TPNQGP', signedIn: true, confirmed: false),
        InviteCodeState.pending,
      );
    });

    test('пустой код ждёт сервера', () {
      expect(
        inviteCodeStateOf(code: '', signedIn: true, confirmed: false),
        InviteCodeState.pending,
      );
      expect(
        inviteCodeStateOf(code: '  ', signedIn: true, confirmed: true),
        InviteCodeState.pending,
      );
    });

    test('подтверждённый код можно раздавать', () {
      expect(
        inviteCodeStateOf(code: 'AB12CD', signedIn: true, confirmed: true),
        InviteCodeState.ready,
      );
    });
  });

  group('журнал кодов, подтверждённых сервером', () {
    setUp(ConfirmedInviteCodes.clear);

    test('код подтверждается за конкретным владельцем', () {
      ConfirmedInviteCodes.confirm('AB12CD', ownerUid: 'u1');
      expect(ConfirmedInviteCodes.contains('AB12CD', ownerUid: 'u1'), isTrue);
      expect(
        ConfirmedInviteCodes.contains('AB12CD', ownerUid: 'u2'),
        isFalse,
        reason: 'после смены аккаунта код прежнего владельца рабочим не считается',
      );
    });

    test('регистр и пробелы кода не важны', () {
      ConfirmedInviteCodes.confirm(' ab12cd ', ownerUid: 'u1');
      expect(ConfirmedInviteCodes.contains('AB12CD', ownerUid: 'u1'), isTrue);
    });

    test('забытый код больше не подтверждён', () {
      ConfirmedInviteCodes.confirm('AB12CD', ownerUid: 'u1');
      ConfirmedInviteCodes.forget('AB12CD');
      expect(ConfirmedInviteCodes.contains('AB12CD', ownerUid: 'u1'), isFalse);
    });

    test('пустой код не подтверждается', () {
      ConfirmedInviteCodes.confirm('', ownerUid: 'u1');
      ConfirmedInviteCodes.confirm('AB12CD', ownerUid: '');
      expect(ConfirmedInviteCodes.contains('', ownerUid: 'u1'), isFalse);
      expect(ConfirmedInviteCodes.contains('AB12CD', ownerUid: ''), isFalse);
    });
  });

  group('связь без сессии (случай TPNQGP)', () {
    // В тестах сессии PocketBase нет: ровно то состояние, в котором был
    // человек 23 сентября.
    test('код из памяти телефона не раздаётся', () {
      final c = Connection(id: 'g1', inviteCode: 'TPNQGP');
      expect(c.inviteCodeState, InviteCodeState.sessionLost);
      expect(c.shareableInviteCode, isEmpty);
    });
  });

  group('что остаётся в поле после сверки с сервером', () {
    test('сервер кода не знает, перевыпуск не прошёл — поле пустеет', () {
      expect(
        Connection.codeAfterServerCheck(
            current: 'TPNQGP', mine: false, fresh: ''),
        '',
        reason: 'мёртвый код нельзя оставлять на экране: партнёр получит '
            '«Код не найден»',
      );
    });

    test('сервер кода не знает, перевыпуск прошёл — встаёт новый', () {
      expect(
        Connection.codeAfterServerCheck(
            current: 'TPNQGP', mine: false, fresh: 'XY99ZZ'),
        'XY99ZZ',
      );
    });

    test('сервер код подтвердил — код остаётся', () {
      expect(
        Connection.codeAfterServerCheck(current: 'AB12CD', mine: true, fresh: ''),
        'AB12CD',
      );
    });

    test('сервер промолчал — код остаётся в поле, но рабочим не считается', () {
      expect(
        Connection.codeAfterServerCheck(current: 'AB12CD', mine: null, fresh: ''),
        'AB12CD',
      );
    });
  });

  group('сторожа по исходникам', () {
    String bodyOf(String src, String signature, {int length = 1800}) {
      final start = src.indexOf(signature);
      expect(start, greaterThan(0),
          reason: '$signature не найден — поправьте сторожа');
      return src.substring(start, (start + length).clamp(0, src.length));
    }

    test('экран подключения раздаёт только подтверждённый код', () {
      final src =
          File('lib/screens/connect_partner_screen.dart').readAsStringSync();
      for (final sig in const [
        'void _handleCopy()',
        'Future<void> _handleShare()',
        'Widget _heroCode(',
        'Widget _actionsRow(',
        'void _showQRDialog()',
      ]) {
        final end = src.indexOf('\n  }\n', src.indexOf(sig));
        final body = src.substring(src.indexOf(sig), end);
        expect(
          body.contains('pair.inviteCode'),
          isFalse,
          reason: '$sig берёт pair.inviteCode напрямую: так на экран снова '
              'попадёт код, которого сервер не подтвердил',
        );
      }
    });

    test('первый экран после регистрации тоже раздаёт только подтверждённый код', () {
      final src =
          File('lib/screens/invite_partner_screen.dart').readAsStringSync();
      for (final sig in const [
        'Future<void> _share()',
        'void _copyCode()',
        'void _showQr()',
        'Widget build(BuildContext context)',
      ]) {
        final start = src.indexOf(sig);
        expect(start, greaterThan(0), reason: '$sig не найден');
        final body = src.substring(start, (start + 400).clamp(0, src.length));
        expect(body.contains('_pair.inviteCode;'), isFalse,
            reason: '$sig берёт неподтверждённый код');
      }
    });

    test('сверка кода гостем не считается ответом сервера', () {
      final src = File('lib/services/pb_data_service.dart').readAsStringSync();
      final body = bodyOf(src, 'Future<bool?> inviteCodeIsMine(');
      final guard = body.indexOf('authStore.isValid');
      final query = body.indexOf("collection('invite_codes')");
      expect(guard, greaterThan(0),
          reason: 'без живого токена сервер отдаёт гостю пустой список, и '
              '404 читался как «кода нет»');
      expect(guard, lessThan(query));
    });

    test('сервер записывает в журнал каждый выданный и подтверждённый код', () {
      final src = File('lib/services/pb_data_service.dart').readAsStringSync();
      expect(
        bodyOf(src, 'Future<String> generateInviteCode(', length: 2600)
            .contains('ConfirmedInviteCodes.confirm('),
        isTrue,
      );
      expect(
        bodyOf(src, 'Future<bool?> inviteCodeIsMine(')
            .contains('ConfirmedInviteCodes.confirm('),
        isTrue,
      );
    });
  });
}
