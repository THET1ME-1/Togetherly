import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/redeem_code.dart';

/// Код из бота: TG-XXXX-XXXX. Алфавит без нуля, O, единицы и I — их путают на
/// слух и на глаз, поэтому бот их и не выдаёт (см. ALPHABET в snt-bot/plus.py).
/// Раз так, ввод обязан их не принимать, а не отдавать серверу заведомый мусор.
void main() {
  group('Очистка ввода', () {
    test('Дефисы и пробелы выкидываются', () {
      expect(RedeemCode.digits('TG-4F2A-B79C'), 'TG4F2AB79C');
      expect(RedeemCode.digits('tg 4f2a b79c'), 'TG4F2AB79C');
    });

    test('Строчные приводятся к прописным', () {
      expect(RedeemCode.digits('tg4f2a'), 'TG4F2A');
    });

    test('Символы вне алфавита не проходят', () {
      expect(RedeemCode.digits('TG-0O1I'), 'TG');
      expect(RedeemCode.digits('ТГ-4F2A'), '4F2A', reason: 'кириллица не в счёт');
    });

    test('Длиннее кода не набрать', () {
      expect(RedeemCode.digits('TG4F2AB79CXXXX').length, RedeemCode.length);
    });
  });

  group('Показ', () {
    test('Дефисы расставляются сами', () {
      expect(RedeemCode.formatted('TG4F2AB79C'), 'TG-4F2A-B79C');
    });

    test('Незаконченный код показывается как есть', () {
      expect(RedeemCode.formatted('TG4F'), 'TG-4F');
      expect(RedeemCode.formatted('TG'), 'TG');
      expect(RedeemCode.formatted(''), '');
    });

    test('Готовность считается по длине', () {
      expect(RedeemCode.isComplete('TG4F2AB79C'), isTrue);
      expect(RedeemCode.isComplete('TG4F2AB19'), isFalse);
    });
  });
}
