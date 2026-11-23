import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/l10n/de/daily_tasks.dart';
import 'package:love_app/l10n/de/gifts.dart';
import 'package:love_app/l10n/de/inline.dart';
import 'package:love_app/l10n/es/daily_tasks.dart';
import 'package:love_app/l10n/es/gifts.dart';
import 'package:love_app/l10n/es/inline.dart';
import 'package:love_app/l10n/fr/daily_tasks.dart';
import 'package:love_app/l10n/fr/gifts.dart';
import 'package:love_app/l10n/fr/inline.dart';
import 'package:love_app/l10n/it/daily_tasks.dart';
import 'package:love_app/l10n/it/gifts.dart';
import 'package:love_app/l10n/it/inline.dart';
import 'package:love_app/l10n/pt/inline.dart';
import 'package:love_app/models/daily_task.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/screens/gifts/gift_memo_sheet.dart';
import 'package:love_app/services/locale_service.dart';

/// Немецкий, французский, испанский и итальянский вне словаря.
///
/// Словарь `lib/l10n/dict/` у них был переведён, а строки из экранов, задания
/// дня, подарки и строки английского класса шли по-английски: таблицы по
/// английскому образцу были только у китайского, украинского и португальского.
/// Владелец 23.11.2026: «А остальные языки приложения для тебя шутка?»
class _Lang {
  const _Lang(this.lang, this.inline, this.tasks, this.gifts, this.hint);

  final AppLanguage lang;
  final Map<String, String> inline;
  final Map<String, String> tasks;
  final Map<String, String> gifts;
  final String Function(GiftAction) hint;
}

const _langs = [
  _Lang(AppLanguage.de, kDeByEnglish, kDailyTasksDe, kGiftTitlesDe, actionHintDe),
  _Lang(AppLanguage.fr, kFrByEnglish, kDailyTasksFr, kGiftTitlesFr, actionHintFr),
  _Lang(AppLanguage.es, kEsByEnglish, kDailyTasksEs, kGiftTitlesEs, actionHintEs),
  _Lang(AppLanguage.it, kItByEnglish, kDailyTasksIt, kGiftTitlesIt, actionHintIt),
];

void main() {
  tearDown(() => LocaleService.instance.setLanguage(AppLanguage.en));

  for (final l in _langs) {
    group(l.lang.code, () {
      test('строки из экранов — все ключи португальской таблицы', () {
        // Португальская таблица покрывает китайскую и украинскую (сторож в
        // locale_pt_test.dart) — это опись строк, живущих вне словаря.
        final missing = kPtByEnglish.keys.where((k) => !l.inline.containsKey(k)).toList();
        final stray = l.inline.keys.where((k) => !kPtByEnglish.containsKey(k)).toList();
        expect(missing, isEmpty, reason: 'нет перевода: ${missing.take(8)}');
        expect(stray, isEmpty, reason: 'лишний ключ (опечатка?): ${stray.take(8)}');
      });

      test('метки чисел те же, что в английской строке', () {
        final mark = RegExp(r'\{\d+\}');
        final broken = <String>[];
        l.inline.forEach((en, tr) {
          final want = mark.allMatches(en).map((m) => m[0]).toSet();
          final got = mark.allMatches(tr).map((m) => m[0]).toSet();
          if (want.length != got.length || !want.containsAll(got)) {
            broken.add('$en: $want ≠ $got');
          }
        });
        expect(broken, isEmpty, reason: broken.take(10).join('\n'));
      });

      test('переводы не пустые и не по-русски', () {
        final cyrillic = RegExp('[А-Яа-яЁё]');
        final bad = [
          ...l.inline.entries.where((e) => e.value.trim().isEmpty || cyrillic.hasMatch(e.value)),
          ...l.tasks.entries.where((e) => e.value.trim().isEmpty || cyrillic.hasMatch(e.value)),
          ...l.gifts.entries.where((e) => e.value.trim().isEmpty || cyrillic.hasMatch(e.value)),
        ].map((e) => e.key);
        expect(bad, isEmpty, reason: '$bad');
      });

      test('задания дня переведены все, имя партнёра на месте', () {
        LocaleService.instance.setLanguage(AppLanguage.en);
        final broken = <String>[];
        for (final task in DailyTask.all) {
          final tr = l.tasks[task.id];
          if (tr == null) {
            broken.add('${task.id}: нет перевода');
          } else if (task.title('ZZ').contains('ZZ') != tr.contains('{p}')) {
            broken.add('${task.id}: {p}');
          }
        }
        expect(broken, isEmpty, reason: broken.take(10).join('\n'));
        final stray = l.tasks.keys.where((id) => !DailyTask.all.any((t) => t.id == id));
        expect(stray, isEmpty, reason: 'опечатка в id: ${stray.take(5)}');
      });

      test('подарки витрины и сундука названы, подсказки действий свои', () {
        final missing = [...GiftCatalog.all, ...GiftCatalog.chest]
            .where((g) => !l.gifts.containsKey(g.key))
            .map((g) => g.key)
            .toList();
        expect(missing, isEmpty, reason: 'подарки: $missing');
        for (final a in GiftAction.values) {
          expect(l.hint(a), isNot(actionHintEn(a)), reason: '$a');
        }
      });

      test('строки английского класса — всё, что переводит португальский', () {
        final member = RegExp(r'^\s*(?:String|List<String>) (?:get )?([a-zA-Z0-9]+)', multiLine: true);
        Set<String> overrides(String lang) => member
            .allMatches(File('lib/services/strings_$lang.dart').readAsStringSync())
            .map((m) => m[1]!)
            .toSet();
        final missing = overrides('pt').difference(overrides(l.lang.code)).toList();
        expect(missing, isEmpty, reason: 'нет в strings_${l.lang.code}.dart: ${missing.take(10)}');
      });

      test('в приложении строки идут на этом языке', () {
        LocaleService.instance.setLanguage(l.lang);
        expect(ruEn('Нет сети', 'Offline'), l.inline['Offline']);
        expect(
          ruEn('Не хватает монет: нужно 30, у вас 12',
              'Not enough coins: 30 needed, you have 12'),
          l.inline['Not enough coins: {0} needed, you have {1}']!
              .replaceAll('{0}', '30')
              .replaceAll('{1}', '12'),
        );
        final task = DailyTask.all.firstWhere((t) => t.id == 'photo_smile');
        expect(task.title('Ana'), l.tasks['photo_smile']!.replaceAll('{p}', 'Ana'));
        final heart = GiftCatalog.all.firstWhere((g) => g.key == 'heart');
        expect(heart.title, l.gifts['heart']);
        expect(LocaleService.current.exportMyData, isNot('My data'));
        expect(giftTimesLabel(3, ru: false), isNot('3 times'));
      });
    });
  }
}
