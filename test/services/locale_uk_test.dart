import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/l10n/uk/daily_tasks.dart';
import 'package:love_app/l10n/uk/gifts.dart';
import 'package:love_app/l10n/uk/inline.dart';
import 'package:love_app/l10n/uk/uk.dart';
import 'package:love_app/l10n/zh/daily_tasks.dart';
import 'package:love_app/l10n/zh/gifts.dart';
import 'package:love_app/l10n/zh/inline.dart';
import 'package:love_app/models/love_test.dart';
import 'package:love_app/services/locale_service.dart';

/// Украинский (TOG-20): колонка из `lib/l10n/uk/`, влитая в словарь, плюс
/// свои числа и даты в `_UkStrings`.
///
/// Отзыв в Google Play 22.10.2026: «из минусов нет украинского языка». Колонка
/// лежит отдельно от разделов `lib/l10n/dict/`, как китайская, поэтому новый
/// ключ легко завести без перевода — первый тест ловит именно это. Перевод
/// делался с русского, и русская буква в украинской строке — верный признак
/// недоперевода; её ловит четвёртый тест.
void main() {
  late AppStrings uk;

  setUp(() {
    LocaleService.instance.setLanguage(AppLanguage.uk);
    uk = LocaleService.instance.strings;
  });

  test('словарь переведён целиком', () {
    final missing = kStrings.entries
        .where((e) => (e.value['uk'] ?? '').isEmpty)
        .map((e) => e.key)
        .toList();
    expect(missing, isEmpty, reason: 'без украинского: ${missing.take(15)}');
  });

  test('строки из экранов, задания дня и подарки — всё, что есть у китайского',
      () {
    // Китайские таблицы собирали обходом экранов: это и есть опись строк,
    // живущих вне словаря.
    final inline =
        kZhByEnglish.keys.where((k) => !kUkByEnglish.containsKey(k)).toList();
    final tasks =
        kDailyTasksZh.keys.where((k) => !kDailyTasksUk.containsKey(k)).toList();
    final gifts =
        kGiftTitlesZh.keys.where((k) => !kGiftTitlesUk.containsKey(k)).toList();
    expect(inline, isEmpty, reason: 'строки экранов: ${inline.take(8)}');
    expect(tasks, isEmpty, reason: 'задания дня: ${tasks.take(8)}');
    expect(gifts, isEmpty, reason: 'подарки: ${gifts.take(8)}');
  });

  test('в колонке нет ключей, которых нет в словаре', () {
    final stray = kUkStrings.keys.where((k) => !kStrings.containsKey(k));
    expect(stray, isEmpty, reason: 'опечатка в ключе: ${stray.take(10)}');
  });

  test('подстановки те же, что в английской строке', () {
    final mark = RegExp(r'\{[A-Za-z_]+\}');
    final broken = <String>[];
    for (final e in kStrings.entries) {
      final en = e.value['en'];
      final ua = e.value['uk'];
      if (en == null || ua == null) continue;
      final want = mark.allMatches(en).map((m) => m[0]).toSet();
      final got = mark.allMatches(ua).map((m) => m[0]).toSet();
      if (want.length != got.length || !want.containsAll(got)) {
        broken.add('${e.key}: $want ≠ $got');
      }
    }
    expect(broken, isEmpty, reason: broken.take(10).join('\n'));
  });

  test('ни русских букв, ни чужих слов', () {
    final russian = RegExp('[ыэъёЫЭЪЁ]');
    final bad = <String>[];
    void check(String where, String text) {
      if (russian.hasMatch(text)) bad.add('$where: $text');
    }

    kUkStrings.forEach(check);
    kUkByEnglish.forEach(check);
    kDailyTasksUk.forEach(check);
    kGiftTitlesUk.forEach(check);
    expect(bad, isEmpty, reason: bad.take(15).join('\n'));
  });

  test('простые строки идут из украинской колонки', () {
    expect(uk.save, 'Зберегти');
    expect(uk.memoryLane, 'Стрічка спогадів');
    expect(uk.coinBalance, 'Монети');
    expect(uk.iMissYou, 'Я сумую');
  });

  test('три формы числа, как в русском', () {
    expect(uk.timerDaysCount(1), '1 день');
    expect(uk.timerDaysCount(2), '2 дні');
    expect(uk.timerDaysCount(5), '5 днів');
    expect(uk.timerDaysCount(11), '11 днів');
    expect(uk.timerDaysCount(21), '21 день');
    expect(uk.timerDaysCount(22), '22 дні');
    expect(uk.coinsPlus(1), '+1 монета');
    expect(uk.coinsPlus(3), '+3 монети');
    expect(uk.coinsPlus(12), '+12 монет');
    expect(uk.tgDaysMilestone(100), '100 днів');
    expect(uk.daysTogetherNotifBody(365), 'Ви разом уже 365 днів ❤️');
  });

  test('даты украинские, месяц в дате стоит в родительном', () {
    expect(uk.fullMonths[3], 'Березень');
    expect(uk.shortWeekdays.first, 'Пн');
    expect(uk.longWeekdays.last, 'Неділя');
    expect(uk.dayLogDate(DateTime(2001, 3, 8)), '8 березня');
    expect(uk.chatDateHeader(DateTime(2001, 3, 8)), '8 березня 2001');
    expect(uk.formatDateAt(uk.fullMonths[3], 8, 2001, '12:30'),
        '8 березня 2001 о 12:30');
  });

  test('подстановка в словарной строке доходит до экрана', () {
    expect(uk.moodYearMissing(3), '3 дні без позначки');
    expect(uk.streakRestored(12), 'Серія повернулася: 12');
  });

  test('строка прямо в экране находит перевод по английскому образцу', () {
    expect(ruEn('Нет сети', 'Offline'), 'Немає мережі');
  });

  test('украинская система ведёт в украинский, а выбранный язык уважаем', () {
    expect(LocaleService.detect(const Locale('uk')), AppLanguage.uk);
    expect(LocaleService.detect(const Locale('uk', 'UA')), AppLanguage.uk);
    // Язык системы выбрал сам человек: русская или английская система в
    // Украине остаётся своей.
    expect(LocaleService.detect(const Locale('ru', 'UA')), AppLanguage.ru);
    expect(LocaleService.detect(const Locale('en', 'UA')), AppLanguage.en);
    // Язык системы, которого у нас нет (крымскотатарский), уходит по стране.
    expect(LocaleService.detect(const Locale('crh', 'UA')), AppLanguage.uk);
  });

  test('локаль приложения украинская', () {
    final l = AppLanguage.uk.locale;
    expect(l.languageCode, 'uk');
    expect(LocaleService.supportedLocales, contains(l));
  });

  test('тест «Умение любить» говорит о партнёре в его роде', () {
    // `\b` в Dart знает только латиницу, поэтому границу слова задаём сами.
    RegExp word(String w) => RegExp(
        '(?<![а-яіїєґ’\'])$w(?![а-яіїєґ’\'])',
        caseSensitive: false,
        unicode: true);
    var sawHer = 0, sawHim = 0;
    for (final q in kLoveBank) {
      final toHer = q.textFor(meFemale: false, partnerFemale: true);
      final toHim = q.textFor(meFemale: true, partnerFemale: false);
      expect(toHer, isNot(contains('{')), reason: q.key);
      expect(toHim, isNot(contains('{')), reason: q.key);
      expect(word('він').hasMatch(toHer), isFalse, reason: '${q.key}: $toHer');
      expect(word('вона').hasMatch(toHim), isFalse,
          reason: '${q.key}: $toHim');
      if (word('вона').hasMatch(toHer)) sawHer++;
      if (word('він').hasMatch(toHim)) sawHim++;
    }
    // Проверка выше прошла бы и впустую, если бы граница слова не работала
    // или текст не был украинским: местоимения должны встречаться.
    expect(sawHer, greaterThan(3));
    expect(sawHim, greaterThan(3));
  });
}
