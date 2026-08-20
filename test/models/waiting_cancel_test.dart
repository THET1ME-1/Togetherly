import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/connection.dart';

/// Отмена ожидания на стороне телефона.
///
/// Пару с пустым местом («он в армии») человек мог завести, а убрать — нет:
/// карточка «Ждём» висела на экране связи вместе с кодом второго места
/// (жалоба 15 августа 2026). Распускает пару сервер, а связь остаётся на месте
/// пустой — в ней живёт код приглашения, и звать настоящего партнёра можно
/// сразу.
///
/// Заглушка живёт и в локальном json, поэтому её надо стирать: иначе после
/// перезапуска «Ждём человека» вернулось бы на экран уже без самой пары.
void main() {
  Connection waitingConn() => Connection(
        id: 'c1',
        isPaired: true,
        pairId: 'grp1',
      )
        ..waitingFlag = true
        ..placeholderName = 'Дима'
        ..placeholderAvatar = 'pb://media/x/y.jpg'
        ..returnDate = DateTime(2027, 5, 15)
        ..claimToken = 'XGZCCTS4'
        ..claimUid = 'uid-2'
        ..claimName = 'Дима'
        ..claimAt = 1755200000000;

  test('связь после отмены не помнит, кого ждали', () {
    final conn = waitingConn()..markUnpaired();

    expect(conn.isPaired, isFalse);
    expect(conn.pairId, isEmpty);
    expect(conn.waitingMode, isFalse);
    expect(conn.placeholderName, isEmpty);
    expect(conn.placeholderAvatar, isEmpty);
    expect(conn.returnDate, isNull);
    expect(conn.claimToken, isEmpty);
    expect(conn.claimUid, isEmpty);
    expect(conn.claimName, isEmpty);
    expect(conn.claimAt, 0);
  });

  test('код приглашения при этом остаётся: звать партнёра есть куда', () {
    final conn = waitingConn()
      ..inviteCode = 'AB12CD'
      ..markUnpaired();

    expect(conn.inviteCode, 'AB12CD');
  });

  test('заглушка не переживает перезапуск приложения', () {
    final conn = waitingConn()..markUnpaired();
    final restored = Connection.fromJson(conn.toJson(), null);

    expect(restored.waitingMode, isFalse);
    expect(restored.placeholderName, isEmpty);
    expect(restored.claimToken, isEmpty);
    expect(restored.hasClaimRequest, isFalse);
  });
}
