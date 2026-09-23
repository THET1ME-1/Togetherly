import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Обращения 164, 178, 183, 190 (сентябрь 2026): на iPhone комната открывалась
// после рекламы, а касания до встроенного браузера не доходили — работали
// только кнопки самого приложения. Две защиты:
// 1. комната открывается, когда реклама закрылась до конца: приложение снова
//    на переднем плане и прошло два кадра;
// 2. касания в зоне браузера сразу отдаются ему (EagerGestureRecognizer), а не
//    ждут решения арены жестов Flutter.
void main() {
  test('браузер комнаты забирает касания сразу', () {
    final src = File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
    final web = src.substring(src.indexOf('InAppWebView('));
    expect(web.substring(0, 900), contains('EagerGestureRecognizer'));
  });

  test('комната открывается только после того, как реклама улеглась', () {
    final src = File('lib/screens/together/together_launcher.dart').readAsStringSync();
    final ad = src.indexOf('_requireStartAd(context)');
    final push = src.indexOf('navigator.push', ad);
    final settle = src.indexOf('_settleAfterAd()', ad);
    expect(settle, greaterThan(ad));
    expect(settle, lessThan(push));
  });
}
