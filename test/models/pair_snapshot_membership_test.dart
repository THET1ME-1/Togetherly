import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/connection.dart';

/// Пара пропадала с экрана, пока на сервере жила.
///
/// 22 августа 2026 три жалобы за один вечер: «перехожу по коду партнёра —
/// пишет, что мы вместе, а в приложении ничего не меняется» (@kssth2),
/// «счётчик был, а потом резко всё исчезло, и пару добавить заново не могу —
/// пишет, что она уже есть» (@shnyrr). В базе обе пары целы: члены на месте,
/// `disbanded = false`. Стирал их сам телефон: живой снимок группы приходил
/// без списка участников (или с пустым), приложение читало это как «меня
/// выгнали» и обнуляло связь.
///
/// Пустой список — это отсутствие данных, а не пустая группа: себя в ней не
/// найдёт никто. То же с неизвестным своим uid — полумёртвая сессия отдаёт
/// пустую строку, и сравнение промахивается по всем участникам сразу.
void main() {
  group('shouldDropMembership', () {
    const me = 'uid-me';
    const partner = GroupMember(uid: 'uid-partner', name: 'Аня');
    const myself = GroupMember(uid: me, name: 'Саша');

    test('меня в непустом составе нет — членство потеряно', () {
      expect(
        shouldDropMembership(members: [partner], myUid: me),
        isTrue,
      );
    });

    test('я в составе — членство на месте', () {
      expect(
        shouldDropMembership(members: [myself, partner], myUid: me),
        isFalse,
      );
    });

    test('пустой состав — это нет данных, а не изгнание', () {
      expect(
        shouldDropMembership(members: const [], myUid: me),
        isFalse,
      );
    });

    test('свой uid неизвестен — сравнивать не с чем, связь не трогаем', () {
      expect(
        shouldDropMembership(members: [partner, myself], myUid: ''),
        isFalse,
      );
    });
  });
}
