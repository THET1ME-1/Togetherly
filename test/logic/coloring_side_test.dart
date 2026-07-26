// Кому какая половина раскраски достаётся. Считается на обоих телефонах
// независимо, поэтому правило должно давать зеркальный результат: если мне
// левая, то партнёру — правая, без переговоров и без записи в базу.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/coloring_picture.dart';

void main() {
  group('coloringSideFor', () {
    test('меньший uid берёт левую половину', () {
      expect(coloringSideFor('aaa', 'bbb'), ColoringSide.left);
    });

    test('больший uid берёт правую', () {
      expect(coloringSideFor('bbb', 'aaa'), ColoringSide.right);
    });

    test('стороны зеркальны', () {
      const a = 'k9x2';
      const b = 'k9x1';
      expect(coloringSideFor(a, b), isNot(coloringSideFor(b, a)));
    });

    test('без партнёра — левая', () {
      expect(coloringSideFor('aaa', ''), ColoringSide.left);
    });

    test('регистр не переставляет половины местами', () {
      expect(coloringSideFor('ABC', 'abd'), coloringSideFor('abc', 'abd'));
    });
  });

  group('ColoringMode', () {
    test('разбор из хранилища', () {
      expect(ColoringMode.fromStorage('together'), ColoringMode.together);
      expect(ColoringMode.fromStorage('surprise'), ColoringMode.surprise);
    });

    test('неизвестное значение — сюрприз', () {
      expect(ColoringMode.fromStorage(null), ColoringMode.surprise);
      expect(ColoringMode.fromStorage('nonsense'), ColoringMode.surprise);
    });

    test('запись и разбор дают то же значение', () {
      for (final mode in ColoringMode.values) {
        expect(ColoringMode.fromStorage(mode.storage), mode);
      }
    });
  });

  group('ColoringPicture.byId', () {
    test('находит картинку каталога', () {
      expect(ColoringPicture.byId('cafe')?.id, 'cafe');
    });

    test('пустой и неизвестный id — null', () {
      expect(ColoringPicture.byId(''), isNull);
      expect(ColoringPicture.byId('nope'), isNull);
    });

    test('у каждой картинки свои ассеты', () {
      for (final p in ColoringPicture.all) {
        expect(p.outlineAsset, 'assets/coloring/${p.id}.png');
        expect(p.thumbAsset, 'assets/coloring/${p.id}_thumb.jpg');
      }
    });
  });
}
