import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/wish_reservation.dart';

WishReservation _res(String id, String wishId, {String uid = 'me'}) =>
    WishReservation(
      id: id,
      wishId: wishId,
      uid: uid,
      createdAt: DateTime.utc(2026, 8, 2),
    );

/// Карточка спрашивает у списка ровно одно: «эту вещь я уже взял?». Список
/// приходит только свой — чужие резервации сервер не отдаёт вовсе.
void main() {
  group('reservedWishIds', () {
    test('собирает желания из списка', () {
      final ids = reservedWishIds([_res('r1', 'w1'), _res('r2', 'w2')]);
      expect(ids, {'w1', 'w2'});
    });

    test('схлопывает повтор по одному желанию', () {
      // Двойное нажатие в офлайне могло положить две записи на одну вещь.
      final ids = reservedWishIds([_res('r1', 'w1'), _res('r2', 'w1')]);
      expect(ids, {'w1'});
    });

    test('пропускает записи без желания', () {
      final ids = reservedWishIds([_res('r1', ''), _res('r2', 'w2')]);
      expect(ids, {'w2'});
    });

    test('пустой список даёт пустой набор', () {
      expect(reservedWishIds(const []), isEmpty);
    });
  });
}
