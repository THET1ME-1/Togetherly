import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Обращение 482 (14.11.2026): на iPhone звание стоит «Искра · 0 мин», хотя
/// приложение открыто больше десяти минут. Счёт часов запускался в `main.dart`
/// только в ветке Android, и за час сервер получил время от 1621 телефона на
/// Android и от одного iPhone. Часы для званий нужны на обеих платформах.
void main() {
  test('счёт часов для званий запускается не только на Android', () {
    final src = File('lib/main.dart').readAsStringSync();
    const call = 'AppTimeService.instance.start()';
    expect(src.contains(call), isTrue, reason: 'счёт часов не запускается вовсе');

    // Ветка Android — блок `else` после проверки iOS, где живёт WorkManager
    final marker = src.indexOf('WidgetBackgroundRefreshService.instance.init()');
    expect(marker, greaterThan(0));
    final open = src.lastIndexOf('} else {', marker) + '} else '.length;
    var depth = 0;
    var close = open;
    for (; close < src.length; close++) {
      if (src[close] == '{') depth++;
      if (src[close] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    final androidBranch = src.substring(open, close);
    expect(androidBranch.contains(call), isFalse,
        reason: 'счёт часов спрятан в ветку Android, на iPhone звание стоит на нуле');
  });
}
