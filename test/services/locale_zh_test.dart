import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/l10n/zh/zh.dart';
import 'package:love_app/models/love_test.dart';
import 'package:love_app/services/locale_service.dart';

/// Китайский (упрощённое письмо): колонка из `lib/l10n/zh/`, влитая в
/// словарь, плюс свои числа и даты в `_ZhStrings`.
///
/// Колонка лежит отдельно от разделов `lib/l10n/dict/`, поэтому новый ключ
/// легко завести без перевода. Первый тест ловит именно это.
void main() {
  late AppStrings zh;

  setUp(() {
    LocaleService.instance.setLanguage(AppLanguage.zh);
    zh = LocaleService.instance.strings;
  });

  test('словарь переведён целиком', () {
    final missing = kStrings.entries
        .where((e) => (e.value['zh'] ?? '').isEmpty)
        .map((e) => e.key)
        .toList();
    expect(missing, isEmpty, reason: 'без китайского: ${missing.take(15)}');
  });

  test('в колонке нет ключей, которых нет в словаре', () {
    final stray = kZhStrings.keys.where((k) => !kStrings.containsKey(k));
    expect(stray, isEmpty, reason: 'опечатка в ключе: ${stray.take(10)}');
  });

  test('подстановки те же, что в английской строке', () {
    final mark = RegExp(r'\{[A-Za-z_]+\}');
    final broken = <String>[];
    for (final e in kStrings.entries) {
      final en = e.value['en'];
      final cn = e.value['zh'];
      if (en == null || cn == null) continue;
      final want = mark.allMatches(en).map((m) => m[0]).toSet();
      final got = mark.allMatches(cn).map((m) => m[0]).toSet();
      if (want.length != got.length || !want.containsAll(got)) {
        broken.add('${e.key}: $want ≠ $got');
      }
    }
    expect(broken, isEmpty, reason: broken.take(10).join('\n'));
  });

  test('ни кириллицы, ни английских слов вне имён и брендов', () {
    // Латиница в китайском интерфейсе допустима только там, где её так и
    // пишут: названия продуктов и площадок, форматы файлов, единицы.
    const allowed = {
      'Togetherly', 'Wallet', 'Google', 'Play', 'Drive', 'Apple', 'App',
      'Store', 'iPhone', 'iOS', 'Android', 'System', 'WebView', 'Chrome',
      'YouTube', 'Shorts', 'TikTok', 'Rutube', 'VK', 'Dzen', 'Vimeo',
      'Dailymotion', 'Instagram', 'Telegram', 'Yandex', 'Disk', 'Kinopoisk',
      'KP', 'Meller1', 'PNG', 'PDF', 'MP4', 'MOV', 'WebM', 'MB', 'PIN', 'UFO',
      'AMOLED', 'Material', 'VPN', 'Wi', 'Fi', 'Photoshop', 'Canva', 'remove',
      'bg', 'lava', 'top', 'gmail', 'com', 'con', 'SnTAppsBot', 'TA',
      // Буквы, которых нет в коде купона: их и надо назвать латиницей.
      'O', 'I',
    };
    final word = RegExp(r'[A-Za-z][A-Za-z0-9]*');
    final bad = <String>[];
    for (final e in kZhStrings.entries) {
      if (RegExp('[а-яА-ЯёЁ]').hasMatch(e.value)) bad.add('${e.key}: кириллица');
      final clean = e.value
          .replaceAll(RegExp(r'\{[A-Za-z_]+\}'), '')
          .replaceAll(RegExp(r'\{[pi]:'), '{');
      for (final m in word.allMatches(clean)) {
        if (!allowed.contains(m[0])) bad.add('${e.key}: «${m[0]}»');
      }
    }
    expect(bad, isEmpty, reason: bad.take(15).join('\n'));
  });

  test('простые строки идут из китайской колонки', () {
    expect(zh.save, '保存');
    expect(zh.memoryLane, '回忆长廊');
    expect(zh.coinBalance, '金币');
    expect(zh.iMissYou, '我想你');
  });

  test('множественного числа нет, у цифры пробел', () {
    expect(zh.timerDaysCount(1), '1 天');
    expect(zh.timerDaysCount(9), '9 天');
    expect(zh.coinsPlus(1), '+1 金币');
    expect(zh.tgDaysMilestone(100), '100 天');
    expect(zh.daysTogetherNotifBody(365), '你们已经在一起 365 天了 ❤️');
  });

  test('даты китайские', () {
    expect(zh.fullMonths[3], '3月');
    expect(zh.shortWeekdays.first, '周一');
    expect(zh.longWeekdays.last, '星期日');
    expect(zh.dayLogDate(DateTime(2001, 3, 8)), '3月8日');
    expect(zh.chatDateHeader(DateTime(2001, 3, 8)), '2001年3月8日');
    expect(zh.formatDateAt(zh.fullMonths[3], 8, 2001, '12:30'),
        '2001年3月8日 12:30');
  });

  test('подстановка в словарной строке доходит до экрана', () {
    expect(zh.moodYearMissing(3), '3 天没有记录');
    expect(zh.streakRestored(12), '连续天数已恢复：12');
  });

  test('язык устройства и страна ведут в китайский', () {
    expect(LocaleService.detect(const Locale('zh')), AppLanguage.zh);
    expect(LocaleService.detect(const Locale('zh', 'TW')), AppLanguage.zh);
    expect(
      LocaleService.detect(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ),
      AppLanguage.zh,
    );
    // Язык системы, которого у нас нет (кантонский), уходит по стране. А
    // английская система в Китае остаётся английской: язык выбран человеком.
    expect(LocaleService.detect(const Locale('yue', 'HK')), AppLanguage.zh);
    expect(LocaleService.detect(const Locale('en', 'CN')), AppLanguage.en);
  });

  test('локаль приложения называет письмо — от неё зависит шрифт иероглифов',
      () {
    final l = AppLanguage.zh.locale;
    expect(l.languageCode, 'zh');
    expect(l.scriptCode, 'Hans');
    expect(LocaleService.supportedLocales, contains(l));
  });

  test('тест «Умение любить» говорит о партнёре в его роде', () {
    for (final q in kLoveBank) {
      final toHer = q.textFor(meFemale: false, partnerFemale: true);
      final toHim = q.textFor(meFemale: true, partnerFemale: false);
      expect(toHer, isNot(contains('{')), reason: q.key);
      expect(toHer.contains('他'), isFalse, reason: '${q.key}: $toHer');
      expect(toHim.contains('她'), isFalse, reason: '${q.key}: $toHim');
    }
  });
}
