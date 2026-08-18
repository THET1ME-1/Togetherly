// Первое подключение — это не переподключение.
//
// После обрыва сокета подписка оживает молча: события, случившиеся в разрыв, не
// приходят никогда, и у двоих расходятся рисунки («нарисовал, а у него нет»).
// Догонять их надо на переподключении, но НЕ на первом соединении: там список
// только что загрузили, и повторный запрос — лишняя работа для сервера.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/reconnect_detector.dart';

void main() {
  test('первое подключение переподключением не считается', () {
    final d = ReconnectDetector();
    expect(d.onConnected(), isFalse);
  });

  test('подключение после обрыва — переподключение', () {
    final d = ReconnectDetector();
    d.onConnected();
    d.onDisconnected();
    expect(d.onConnected(), isTrue);
  });

  test('повтор события подключения без обрыва ничего не значит', () {
    final d = ReconnectDetector();
    d.onConnected();
    expect(d.onConnected(), isFalse,
        reason: 'иначе дубль события заставит всех разом перекачать списки');
  });

  test('обрывов подряд может быть сколько угодно', () {
    final d = ReconnectDetector();
    d.onConnected();
    d.onDisconnected();
    d.onDisconnected();
    expect(d.onConnected(), isTrue);
    d.onDisconnected();
    expect(d.onConnected(), isTrue);
  });
}
