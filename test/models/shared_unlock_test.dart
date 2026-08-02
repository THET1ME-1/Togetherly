import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/level.dart';
import 'package:love_app/models/mascot.dart';

/// Купленный маскот общий на пару.
///
/// Персонаж живёт на главной у обоих, серию они растят вдвоём — значит и
/// покупка одного открывает его второму. Владение поэтому лежит и у покупателя
/// (навсегда, даже если пара разойдётся), и в самой группе (пока вместе).
void main() {
  group('Что купила пара', () {
    test('Пусто у группы, которая ничего не покупала', () {
      expect(GroupMascotState.parseOwned(null), isEmpty);
    });

    test('Список ключей разбирается', () {
      final owned = GroupMascotState.parseOwned(['mascot:kuku', 'mascot:migun']);
      expect(owned, {'mascot:kuku', 'mascot:migun'});
    });

    test('Строка json разбирается так же', () {
      // PocketBase отдаёт json-поле то списком, то строкой — смотря пришло оно
      // по сети или поднялось из офлайн-кэша.
      expect(
        GroupMascotState.parseOwned('["mascot:kuku"]'),
        {'mascot:kuku'},
      );
    });

    test('Мусор не роняет разбор', () {
      expect(GroupMascotState.parseOwned('не json'), isEmpty);
      expect(GroupMascotState.parseOwned(42), isEmpty);
      expect(GroupMascotState.parseOwned(['ok:1', 7, null]), {'ok:1'});
    });
  });

  group('Кому открыт купленный маскот', () {
    final paid = Unlock.fromJson({'type': 'premium', 'price': 100});
    const key = 'mascot:kuku';

    test('Купил сам — открыт', () {
      expect(
        paid.isUnlocked(level: 1, owned: true, plus: false),
        isTrue,
      );
    });

    test('Купил партнёр — открыт и мне', () {
      const state = GroupMascotState(ownedFeatures: {key});
      expect(state.owns(key), isTrue);
      expect(
        paid.isUnlocked(level: 1, owned: state.owns(key), plus: false),
        isTrue,
      );
    });

    test('Никто не покупал — закрыт', () {
      const state = GroupMascotState();
      expect(state.owns(key), isFalse);
      expect(
        paid.isUnlocked(level: 1, owned: state.owns(key), plus: false),
        isFalse,
      );
    });

    test('Чужая покупка другого персонажа не открывает этого', () {
      const state = GroupMascotState(ownedFeatures: {'mascot:migun'});
      expect(state.owns(key), isFalse);
    });
  });
}
