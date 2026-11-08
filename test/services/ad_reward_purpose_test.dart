import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Отзыв 08.11.2026: «реклама с монетами один раз в день». Все ролики
/// приложения шли в одно начисление и тратили дневной счётчик монет, и после
/// сундука или пробы темы кнопка «Посмотреть рекламу» отвечала «лимит».
/// Теперь монеты платит только ролик, показанный с `forCoins: true`, и такой
/// ролик в приложении один — кнопка в профиле.
void main() {
  test('монеты за ролик просит только кнопка в профиле', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final n = RegExp(r'\.show\([^)]*forCoins:\s*true').allMatches(f.readAsStringSync()).length;
      for (var i = 0; i < n; i++) {
        hits.add(f.path);
      }
    }
    expect(hits, ['lib/screens/profile_screen.dart']);
  });

  test('начисление говорит серверу цель ролика', () {
    final src = File('lib/services/pb_coins_service.dart').readAsStringSync();
    expect(src, contains("'purpose': forCoins ? 'coins' : 'other'"));
  });
}
