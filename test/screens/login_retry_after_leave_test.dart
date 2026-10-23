import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «Повторить» в сообщении об обрыве входа через Google или Apple.
///
/// Bugsink 23.10.2026, версия 1.38.0: «Null check operator used on a null
/// value» в `_oauthSignIn`. Сообщение с кнопкой живёт восемь секунд в общем
/// ScaffoldMessenger и переживает экран входа: человек уже ушёл дальше, жмёт
/// «Повторить», и повтор зовёт `setState` у снятого экрана.
void main() {
  test('повтор входа через провайдера ничего не делает на снятом экране', () {
    final src = File('lib/screens/login_screen.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _oauthSignIn(String provider) async {');
    expect(start, isNot(-1));
    final body = src.substring(start, start + 400);
    final firstLine = body
        .split('\n')
        .skip(1)
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && !l.startsWith('//'));
    expect(firstLine, 'if (!mounted) return;');
  });
}
