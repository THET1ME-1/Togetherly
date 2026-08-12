import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/coloring_picture.dart';

/// Раскраска делится пополам: левая половина одному, правая другому. Пока
/// партнёра нет, делить не на кого — но сторона по умолчанию левая, и касания по
/// правой стороне молча пропадали. Со стороны это выглядит так: «кисти не
/// работают просто».
void main() {
  group('coloringSplitApplies', () {
    test('без партнёра половин нет', () {
      expect(coloringSplitApplies(''), isFalse);
      expect(coloringSplitApplies('   '), isFalse);
    });

    test('с партнёром лист делится', () {
      expect(coloringSplitApplies('abc123'), isTrue);
    });
  });

  group('coloringSideFor', () {
    test('стороны у пары разные', () {
      const a = 'aaa111';
      const b = 'zzz999';
      expect(coloringSideFor(a, b), isNot(coloringSideFor(b, a)));
    });

    test('сторона не зависит от того, кто открыл экран', () {
      const a = 'aaa111';
      const b = 'zzz999';
      // Дважды подряд — тот же ответ: иначе половины менялись бы местами и
      // мазки уезжали бы на чужую сторону.
      expect(coloringSideFor(a, b), coloringSideFor(a, b));
      expect(coloringSideFor(b, a), coloringSideFor(b, a));
    });

    test('регистр в идентификаторах ничего не меняет', () {
      expect(coloringSideFor('AAA111', 'zzz999'),
          coloringSideFor('aaa111', 'ZZZ999'));
    });
  });

  group('обмен половинами', () {
    const a = 'aaa111';
    const b = 'zzz999';

    test('обмен переворачивает сторону', () {
      expect(coloringSideFor(a, b, swapped: true),
          isNot(coloringSideFor(a, b)));
    });

    test('после обмена половины остаются зеркальными', () {
      expect(coloringSideFor(a, b, swapped: true),
          isNot(coloringSideFor(b, a, swapped: true)));
    });

    test('без партнёра обмен ничего не меняет: делить не на кого', () {
      expect(coloringSideFor(a, '', swapped: true), coloringSideFor(a, ''));
    });
  });
}
