import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_reaction.dart';

void main() {
  group('набор значков', () {
    test('ключи уникальны и не пусты', () {
      final keys = kMemoryReactions.map((r) => r.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(keys.any((k) => k.trim().isEmpty), isFalse);
    });

    test('сердце стоит первым — им отмечают чаще всего', () {
      expect(kMemoryReactions.first.key, 'heart');
    });

    test('значок по ключу находится, незнакомый откатывается на сердце', () {
      expect(reactionByKey('mood').key, 'mood');
      expect(reactionByKey('нет-такого').key, 'heart');
    });
  });

  group('разбор карты реакций', () {
    test('пустое и мусорное значение дают пустую карту', () {
      expect(parseReactions(null), isEmpty);
      expect(parseReactions('строка'), isEmpty);
      expect(parseReactions(const []), isEmpty);
    });

    test('карта uid → ключ читается как есть', () {
      final r = parseReactions({'u1': 'heart', 'u2': 'mood'});
      expect(r, {'u1': 'heart', 'u2': 'mood'});
    });

    test('незнакомый значок выбрасывается, а не ломает запись', () {
      final r = parseReactions({'u1': 'heart', 'u2': 'выдумка'});
      expect(r, {'u1': 'heart'});
    });

    test('пустой ключ значка означает снятую реакцию', () {
      final r = parseReactions({'u1': '', 'u2': 'mood'});
      expect(r, {'u2': 'mood'});
    });
  });

  group('правка реакции', () {
    test('своя реакция ставится', () {
      final r = withReaction(const {}, 'u1', 'heart');
      expect(r, {'u1': 'heart'});
    });

    test('повторный тот же значок снимает реакцию', () {
      final r = withReaction(const {'u1': 'heart'}, 'u1', 'heart');
      expect(r, isEmpty);
    });

    test('другой значок заменяет прежний — у человека она одна', () {
      final r = withReaction(const {'u1': 'heart'}, 'u1', 'mood');
      expect(r, {'u1': 'mood'});
    });

    test('чужая реакция не трогается', () {
      final r = withReaction(const {'u2': 'mood'}, 'u1', 'heart');
      expect(r, {'u1': 'heart', 'u2': 'mood'});
    });

    test('пустой значок снимает реакцию', () {
      final r = withReaction(const {'u1': 'heart'}, 'u1', '');
      expect(r, isEmpty);
    });
  });

  test('в паре реакций не больше двух — счётчика лайков тут не бывает', () {
    var r = withReaction(const {}, 'u1', 'heart');
    r = withReaction(r, 'u2', 'mood');
    r = withReaction(r, 'u1', 'fire');
    expect(r.length, 2);
    expect(r['u1'], 'fire');
  });
}
