import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Обращения 164, 178, 183, 190 (сентябрь 2026): на iPhone касания до
// встроенного браузера комнаты не доходили — работали только кнопки самого
// приложения. Касания в зоне браузера сразу отдаются ему
// (EagerGestureRecognizer), а не ждут решения арены жестов Flutter. Рекламы
// перед комнатой с 19.10.2026 нет вовсе, её сторож —
// room_exit_ad_wiring_test.dart.
void main() {
  test('браузер комнаты забирает касания сразу', () {
    final src = File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
    final web = src.substring(src.indexOf('InAppWebView('));
    expect(web.substring(0, 900), contains('EagerGestureRecognizer'));
  });
}
