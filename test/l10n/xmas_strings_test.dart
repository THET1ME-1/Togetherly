import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/l10n/dict/xmas.dart';
import 'package:love_app/l10n/uk/xmas.dart';
import 'package:love_app/l10n/xmas_text.dart';
import 'package:love_app/l10n/zh/xmas.dart';

/// Ёлка говорит на всех девяти языках приложения: пропавший перевод показал
/// бы английский посреди русского экрана.
void main() {
  const langs = ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de'];

  test('каждая строка есть на семи языках словаря', () {
    final gaps = [
      for (final e in xmasStrings.entries)
        for (final l in langs)
          if ((e.value[l] ?? '').trim().isEmpty) '${e.key}:$l',
    ];
    expect(gaps, isEmpty);
  });

  test('украинский и китайский покрывают все ключи и ничего лишнего', () {
    expect(xmasUk.keys.toSet(), xmasStrings.keys.toSet());
    expect(xmasZh.keys.toSet(), xmasStrings.keys.toSet());
  });

  test('метки подстановки совпадают во всех переводах', () {
    final re = RegExp(r'\{(\w+)\}');
    for (final e in xmasStrings.entries) {
      final want = re.allMatches(e.value['ru']!).map((m) => m[1]).toSet();
      for (final l in langs) {
        expect(re.allMatches(e.value[l]!).map((m) => m[1]).toSet(), want, reason: '${e.key}:$l');
      }
      expect(re.allMatches(xmasUk[e.key]!).map((m) => m[1]).toSet(), want, reason: '${e.key}:uk');
      expect(re.allMatches(xmasZh[e.key]!).map((m) => m[1]).toSet(), want, reason: '${e.key}:zh');
    }
  });

  test('числа: 1 игрушка, 3 игрушки, 5 и 11 игрушек, 21 игрушка', () {
    expect([1, 3, 5, 11, 21, 22, 112].map((n) => xtPluralForm(n, 'ru')).toList(), [1, 2, 5, 5, 1, 2, 5]);
    expect([1, 2, 5].map((n) => xtPluralForm(n, 'en')).toList(), [1, 5, 5]);
  });

  test('подсказки — одно предложение', () {
    for (final k in ['xt.pickFirst', 'xt.notHere', 'xt.aboutChest', 'xt.aboutShop', 'xt.noCoins']) {
      final ru = xmasStrings[k]!['ru']!;
      expect(RegExp(r'[.!?](\s|$)').allMatches(ru).length, 1, reason: k);
    }
  });
}
