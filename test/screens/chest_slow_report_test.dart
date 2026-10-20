import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «Сундук открывался долго» меряется от закрытия рекламы, а не от нажатия.
///
/// До 20.10.2026 секундомер шёл с нажатия, и в отчёт попадал сам ролик
/// (30–90 секунд): почти каждое открытие за рекламу уходило в Bugsink как
/// `chest: не открылся — slow`, 52 тысячи событий. Они вытесняли из хранилища
/// настоящие ошибки, и отчёты с 1.37.1 пропали через несколько часов.
void main() {
  test('после рекламы секундомер открытия начинается заново', () {
    final source = File('lib/screens/chest_screen.dart').readAsStringSync();
    final adEnd = source.indexOf('adShown = true;');
    final slowCheck = source.indexOf("'slow'");
    expect(adEnd, greaterThan(0));
    expect(slowCheck, greaterThan(adEnd));
    final between = source.substring(adEnd, slowCheck);
    expect(between, contains('total.reset()'), reason: 'время ролика не должно попадать в «долго»');
  });
}
