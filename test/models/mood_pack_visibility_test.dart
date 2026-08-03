import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_pack.dart';

void main() {
  group('Видимость платного пака', () {
    test('на iPhone закрытый платный набор скрыт', () {
      expect(
        moodPackVisible(isIOS: true, isMoney: true, isOpen: false),
        isFalse,
      );
    });

    test('на iPhone открытый платный набор виден', () {
      // Купить могли на Android или на сайте — покупка общая на пару.
      expect(
        moodPackVisible(isIOS: true, isMoney: true, isOpen: true),
        isTrue,
      );
    });

    test('на Android закрытый платный набор виден: его можно купить', () {
      expect(
        moodPackVisible(isIOS: false, isMoney: true, isOpen: false),
        isTrue,
      );
    });

    test('бесплатный набор виден везде', () {
      expect(moodPackVisible(isIOS: true, isMoney: false, isOpen: false), isTrue);
      expect(moodPackVisible(isIOS: false, isMoney: false, isOpen: false), isTrue);
    });
  });
}
