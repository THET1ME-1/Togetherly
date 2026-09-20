// Род в тесте «Умение любить» (19.09.2026).
//
// Жалобы из приёмной: «Я парень, вопросы в тесте на которые должна отвечать
// партнёрша» (обращение 172, на снимке «Мне нравится он такой, какой есть
// сегодня») и «пол указан мой, т.е. мужской, но в тестах… в женском роде»
// (обращение 154). Все утверждения говорили о партнёре «он», а в трёх
// отвечающий был мужчиной («сколько беру сам»). Теперь в тексте метки
// `{p:он|она}` (род партнёра) и `{i:сам|сама}` (род отвечающего).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/models/love_test.dart';
import 'package:love_app/services/locale_service.dart';

void main() {
  test('метки раскрываются по роду партнёра и отвечающего', () {
    const s = 'Мириться {i:первым|первой} я иду не реже, чем {p:он|она}';
    expect(genderize(s, partnerFemale: false, meFemale: false),
        'Мириться первым я иду не реже, чем он');
    expect(genderize(s, partnerFemale: true, meFemale: true),
        'Мириться первой я иду не реже, чем она');
    expect(genderize('без меток', partnerFemale: true, meFemale: true),
        'без меток');
  });

  test('чей род берётся: пол партнёра, а без него — противоположный своему', () {
    expect(loveGenders(myGender: 'male', partnerGender: 'female'),
        (meFemale: false, partnerFemale: true));
    expect(loveGenders(myGender: 'female', partnerGender: 'female'),
        (meFemale: true, partnerFemale: true));
    expect(loveGenders(myGender: 'male', partnerGender: ''),
        (meFemale: false, partnerFemale: true));
    expect(loveGenders(myGender: 'female', partnerGender: ''),
        (meFemale: true, partnerFemale: false));
    expect(loveGenders(myGender: '', partnerGender: ''),
        (meFemale: false, partnerFemale: false));
  });

  group('русский', () {
    setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

    test('снимок из жалобы: парню про партнёршу — «она такая»', () {
      final q = kLoveBank.firstWhere((q) => q.key == 'love_q80');
      expect(q.textFor(meFemale: false, partnerFemale: true),
          'Мне нравится она такая, какая есть сегодня');
      expect(q.textFor(meFemale: true, partnerFemale: false),
          'Мне нравится он такой, какой есть сегодня');
      final q52 = kLoveBank.firstWhere((q) => q.key == 'love_q52');
      expect(q52.textFor(meFemale: false, partnerFemale: true),
          'Я спрашиваю её мнение, прежде чем решить за нас двоих');
    });

    test('про партнёршу не остаётся ни одного мужского местоимения', () {
      final he = RegExp(r'(?<![А-Яа-яЁё])(он|его|ему|него|нему|ним|нём)(?![А-Яа-яЁё])',
          caseSensitive: false);
      for (final q in kLoveBank) {
        final t = q.textFor(meFemale: true, partnerFemale: true);
        expect(he.hasMatch(t), isFalse, reason: '${q.key}: $t');
        expect(RegExp(r'\b(сам|первым я)\b').hasMatch(t), isFalse,
            reason: '${q.key}: $t');
      }
    });
  });

  // Колонки de, fr, pt, es, it размечены тем же приёмом, что русская
  // (19.09.2026): до этого немец, француз и остальные читали про свою девушку
  // «er», «il», «ele», как русский парень читал «он».
  group('de/fr/pt: про партнёршу нет мужских местоимений', () {
    tearDown(() => LocaleService.instance.setLanguage(AppLanguage.ru));

    test('de: ни er, ihn, ihm, sein…, ни «mein Partner»', () async {
      final he = _word(r'er|ihn|ihm|sein(?:e|en|em|er|es)?|mein(?:em)? Partner');
      expect(_offenders('de', he), isEmpty);

      await LocaleService.instance.setLanguage(AppLanguage.de);
      expect(_q('love_q80').textFor(meFemale: false, partnerFemale: true),
          'Ich mag sie so, wie sie heute ist');
      expect(_q('love_q1').textFor(meFemale: false, partnerFemale: true),
          'Ich merke, dass es meiner Partnerin schlecht geht, bevor sie es sagt');
      expect(_q('love_q80').textFor(meFemale: true, partnerFemale: false),
          'Ich mag ihn so, wie er heute ist');
    });

    test('fr: ни il, ни ударного lui, ни мужского согласования', () async {
      // Безличное «il» (Il m’est facile, qu’il ne faut) к партнёру отношения
      // не имеет. Дательное «lui» (je lui parle) одинаково для обоих родов,
      // поэтому ловим только ударное — после предлога и в сравнении.
      final il = RegExp(r'(?<!\p{L})il(?!\p{L})(?! m’est| ne faut)',
          unicode: true, caseSensitive: false);
      final stressedLui = _word(r'(?:de|avec|chez|devant|pour|que|à côté de) lui');
      final masc = _word(r'occupé|fatigué|beau|tel|mon partenaire');
      expect(_offenders('fr', il), isEmpty);
      expect(_offenders('fr', stressedLui), isEmpty);
      expect(_offenders('fr', masc), isEmpty);

      await LocaleService.instance.setLanguage(AppLanguage.fr);
      expect(_q('love_q80').textFor(meFemale: false, partnerFemale: true),
          'Je l’aime telle qu’elle est aujourd’hui');
      expect(_q('love_q13').textFor(meFemale: false, partnerFemale: true),
          'Elle reçoit de moi autant d’attention que j’en reçois d’elle');
      // Отвечающая: «ce qui m’a blessée» — причастие согласуется с «m’».
      expect(_q('love_q7').textFor(meFemale: true, partnerFemale: false),
          'Je dis ce qui m’a blessée au lieu de l’accumuler');
      expect(_q('love_q7').textFor(meFemale: false, partnerFemale: true),
          'Je dis ce qui m’a blessé au lieu de l’accumuler');
    });

    test('pt: ни ele, dele, nele, ни -lo', () async {
      final he = _word(r'ele|dele|nele|cansado');
      final enclitic = RegExp(r'-lo(?!\p{L})', unicode: true);
      expect(_offenders('pt', he), isEmpty);
      expect(_offenders('pt', enclitic), isEmpty);

      await LocaleService.instance.setLanguage(AppLanguage.pt);
      expect(_q('love_q80').textFor(meFemale: false, partnerFemale: true),
          'Gosto dela como ela é hoje');
      expect(_q('love_q15').textFor(meFemale: false, partnerFemale: true),
          'Tenho vontade de tocá-la sem motivo');
    });
  });

  group('es/it: про партнёршу нет мужских форм', () {
    tearDown(() => LocaleService.instance.setLanguage(AppLanguage.ru));

    test('es: ни él, ни lo про партнёра, ни ocupado/cansado', () async {
      // Местоимение-подлежащее испанский опускает, род остаётся в «él» после
      // предлога, в «lo» при глаголе и в согласовании. Среднее «lo» (lo que,
      // a lo largo, acumularlo) роду не подчиняется, поэтому список точный.
      final masc = _word(r'él|ocupado|cansado|tocarlo|sorprenderlo|cambiarlo'
          r'|lo (?:elogio|escucho|abrazo|echo|corrijo|comparo)');
      expect(_offenders('es', masc), isEmpty);

      await LocaleService.instance.setLanguage(AppLanguage.es);
      expect(_q('love_q64').textFor(meFemale: false, partnerFemale: true),
          'La echo de menos a lo largo del día');
    });

    test('it: ни lui, gli, «il mio partner», ни мужского согласования',
        () async {
      final masc = _word(r'lui|gli|il mio partner|occupato|stanco|toccarlo'
          r'|sorprenderlo|cambiarlo|dirgli'
          r'|lo (?:rendono|lodo|ascolto|aiuto|abbraccio|correggo|paragono)');
      expect(_offenders('it', masc), isEmpty);

      await LocaleService.instance.setLanguage(AppLanguage.it);
      expect(_q('love_q67').textFor(meFemale: false, partnerFemale: true),
          'Le dico cosa mi attrae di lei');
      expect(_q('love_q7').textFor(meFemale: true, partnerFemale: false),
          'Dico ciò che mi ha ferita invece di accumularlo');
    });
  });

  test('во всех языках метки закрыты и раскрываются без остатка', () {
    for (final q in kLoveBank) {
      for (final lang in kStrings[q.key]!.keys) {
        final raw = kStrings[q.key]![lang]!;
        for (final pf in [false, true]) {
          for (final mf in [false, true]) {
            final t = genderize(raw, partnerFemale: pf, meFemale: mf);
            expect(t.contains('{') || t.contains('}') || t.contains('|'),
                isFalse,
                reason: '${q.key}/$lang: $t');
          }
        }
      }
    }
  });

  test('экран теста подставляет род, а не голый текст', () {
    final src = File('lib/screens/love_test_screen.dart').readAsStringSync();
    expect(src, contains('q.textFor('));
    expect(src, isNot(contains('q.text,')));
    for (final f in ['lib/screens/home_screen.dart', 'lib/screens/profile_screen.dart']) {
      final call = File(f).readAsStringSync();
      final i = call.indexOf('LoveTestScreen(');
      expect(call.substring(i, i + 400), contains('partnerGender:'), reason: f);
    }
  });
}

LoveQuestion _q(String key) => kLoveBank.firstWhere((q) => q.key == key);

/// Целое слово или оборот: `\b` в Dart знает только латиницу без диакритики,
/// и на «él», «occupé», «à côté» он промахивается.
RegExp _word(String alternatives) => RegExp(
      '(?<!\\p{L})(?:$alternatives)(?!\\p{L})',
      unicode: true,
      caseSensitive: false,
    );

/// Утверждения языка, где про партнёршу нашлось запрещённое, — при любом роде
/// отвечающего.
List<String> _offenders(String lang, RegExp bad) => [
      for (final q in kLoveBank)
        for (final meFemale in [false, true])
          if (bad.hasMatch(genderize(kStrings[q.key]![lang]!,
              partnerFemale: true, meFemale: meFemale)))
            '${q.key}/$lang: '
                '${genderize(kStrings[q.key]![lang]!, partnerFemale: true, meFemale: meFemale)}',
    ];
