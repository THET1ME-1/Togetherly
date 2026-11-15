import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/watch_voice_service.dart';

// Кто звонит первым, тот зовёт в пустоту: у второго микрофон ещё выключен, и
// его «voice-hello» он пропускает. Когда второй нажимает трубку, зов приходит
// первому — и если первый «вежливый» (uid меньше), он молчал и ждал
// предложения, которого второй не сделает никогда. Звонок висел на «Ждём
// ответа» (обращение 648, 15.11.2026).
void main() {
  group('ответ на voice-hello', () {
    test('невежливый на зов делает предложение', () {
      expect(helloAction(me: 'b', from: 'a', reply: false, offered: false), HelloAction.offer);
    });

    test('вежливый на зов отвечает своим зовом, чтобы второй узнал о нём', () {
      expect(helloAction(me: 'a', from: 'b', reply: false, offered: false), HelloAction.callBack);
    });

    test('вежливый на ответный зов молчит: иначе зовы ходили бы по кругу', () {
      expect(helloAction(me: 'a', from: 'b', reply: true, offered: false), HelloAction.none);
    });

    test('невежливый не шлёт второе предложение, если первое уже ушло', () {
      expect(helloAction(me: 'b', from: 'a', reply: true, offered: true), HelloAction.none);
    });

    test('первый позвонил в пустоту, второй нажал трубку — связь всё равно встаёт', () {
      // a < b, значит a вежливый. a звонил первым, его зов b пропустил.
      // b включился и позвал: a отвечает зовом, b на него делает предложение.
      final atA = helloAction(me: 'a', from: 'b', reply: false, offered: false);
      expect(atA, HelloAction.callBack);
      final atB = helloAction(me: 'b', from: 'a', reply: true, offered: false);
      expect(atB, HelloAction.offer);
    });
  });
}
