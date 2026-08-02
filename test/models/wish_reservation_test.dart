import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/wish_reservation.dart';

/// Резервация «дарю» лежит отдельной записью, а не полем желания: правило
/// чтения `wishes` отдаёт запись целиком обоим, и автор увидел бы сюрприз
/// сразу. Тут проверяется только перекладка полей — прятать умеет коллекция.
void main() {
  group('WishReservation', () {
    test('в тело запроса кладёт желание, группу и того, кто дарит', () {
      final res = WishReservation(
        id: 'r1',
        wishId: 'w1',
        uid: 'u1',
        createdAt: DateTime.utc(2026, 8, 2, 12, 30),
      );

      expect(res.toMap(groupId: 'g1'), {
        'id': 'r1',
        'group_id': 'g1',
        'wish_id': 'w1',
        'uid': 'u1',
        'created': '2026-08-02T12:30:00.000Z',
      });
    });

    test('читается обратно из тела записи', () {
      final res = WishReservation.fromMap({
        'id': 'r1',
        'group_id': 'g1',
        'wish_id': 'w1',
        'uid': 'u1',
        'created': '2026-08-02T12:30:00.000Z',
      });

      expect(res.id, 'r1');
      expect(res.wishId, 'w1');
      expect(res.uid, 'u1');
      expect(res.createdAt, DateTime.utc(2026, 8, 2, 12, 30));
    });

    test('переживает запись без даты', () {
      // Сервер отдаёт `created` автополем, но в очереди отправки запись
      // рождается локально и может уйти в кэш до ответа.
      final res = WishReservation.fromMap({'id': 'r2', 'wish_id': 'w2', 'uid': 'u1'});
      expect(res.wishId, 'w2');
      expect(res.createdAt, isNotNull);
    });
  });
}
