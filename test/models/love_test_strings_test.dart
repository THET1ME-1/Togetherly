import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/l10n/dict/love_test.dart';
import 'package:love_app/models/love_test.dart';

/// Тест «Умение любить» на семи языках.
///
/// Утверждения, грани и градации ответа лежали строками прямо в модели — только
/// по-русски. Немец, испанец и все остальные читали русский текст (жалоба
/// 18.08.2026). Заодно утверждение №9 обрывалось на полуслове: «Я замечаю, что
/// он для меня меняет».
void main() {
  const langs = ['ru', 'en', 'de', 'fr', 'es', 'it', 'pt'];

  /// Ключи, которые обязан покрывать словарь.
  final keys = <String>[
    for (final q in kLoveBank) q.key,
    for (final f in LoveFacet.values) 'love_facet_${f.name}',
    for (var i = 0; i < kLoveWeights.length; i++) 'love_answer_$i',
  ];

  test('каждый ключ переведён на все семь языков', () {
    final missing = <String>[];
    for (final key in keys) {
      final row = loveTestStrings[key];
      if (row == null) {
        missing.add('$key: нет в словаре');
        continue;
      }
      for (final lang in langs) {
        final value = row[lang];
        if (value == null || value.trim().isEmpty) missing.add('$key ($lang)');
      }
    }
    expect(missing, isEmpty, reason: missing.join(', '));
  });

  test('перевод не оставлен русским текстом', () {
    final cyrillic = RegExp(r'[А-Яа-яЁё]');
    final leftovers = <String>[];
    for (final key in keys) {
      for (final lang in langs.where((l) => l != 'ru')) {
        final value = loveTestStrings[key]?[lang] ?? '';
        if (cyrillic.hasMatch(value)) leftovers.add('$key ($lang): «$value»');
      }
    }
    expect(leftovers, isEmpty, reason: leftovers.join('\n'));
  });

  test('банк на восемьдесят утверждений, все разные', () {
    expect(kLoveBank.length, 80);
    expect(kLoveBank.map((q) => q.key).toSet().length, 80);
    final texts = {
      for (final lang in langs)
        lang: kLoveBank.map((q) => loveTestStrings[q.key]![lang]).toSet(),
    };
    for (final entry in texts.entries) {
      expect(entry.value.length, 80,
          reason: 'в языке ${entry.key} есть повторяющиеся утверждения');
    }
  });

  test('каждой грани хватает утверждений на несколько проходов подряд', () {
    // Иначе «не повторять прошлый набор» упрётся в пустоту: в грани должно
    // лежать заметно больше, чем берётся за один раз.
    for (final entry in kLoveRoundLayout.entries) {
      final have = kLoveBank.where((q) => q.facet == entry.key).length;
      expect(have, greaterThanOrEqualTo(entry.value * 3),
          reason: 'грань ${entry.key.name}: $have утверждений');
    }
    expect(
      kLoveRoundLayout.values.fold<int>(0, (a, b) => a + b),
      kLoveRoundSize,
    );
  });

  test('утверждение про перемены не обрывается на полуслове', () {
    final ru = loveTestStrings['love_q9']!['ru']!;
    expect(ru, contains('меняется'));
    expect(ru, isNot(contains('для меня меняет')));
  });

  test('текст утверждения приходит из словаря', () {
    // trKey читает выбранный язык; по умолчанию в тестах это русский.
    expect(kLoveBank.first.text, trKey('love_q1'));
    expect(kLoveBank.first.text, isNot('love_q1'));
    expect(LoveFacet.gratitude.title, isNotEmpty);
    expect(kLoveAnswers.length, kLoveWeights.length);
  });
}
