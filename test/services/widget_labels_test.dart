import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/l10n/dict/home_widgets.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/widget_labels.dart';

/// Подписи виджетов рабочего стола на языке приложения (отзыв в App Store
/// 19.08.2026: «The notification and widgets are in Russian though the app I
/// have set to English»). Нативный код читает `wl_<ключ>` и без него берёт
/// русский — поэтому ключи в Dart, Kotlin и Swift обязаны совпадать.
void main() {
  test('каждая подпись переведена на все девять языков', () {
    for (final key in homeWidgetsStrings.keys) {
      for (final lang in AppLanguage.values) {
        expect(kStrings[key]?[lang.code], isNotNull, reason: '$key: нет ${lang.code}');
      }
    }
  });

  test('подстановки одни и те же во всех языках', () {
    final mark = RegExp(r'\{[a-z]+\}');
    for (final key in homeWidgetsStrings.keys) {
      final ru = mark.allMatches(kStrings[key]!['ru']!).map((m) => m[0]).toSet();
      for (final lang in AppLanguage.values) {
        final got = mark.allMatches(kStrings[key]![lang.code]!).map((m) => m[0]).toSet();
        expect(got, ru, reason: '$key/${lang.code}');
      }
    }
  });

  test('списки: двенадцать месяцев, семь дней, десять порядковых', () {
    for (final lang in AppLanguage.values) {
      expect(trDict('wlMonthsGen', lang.code).split(','), hasLength(12), reason: lang.code);
      expect(trDict('wlWeekdays', lang.code).split(','), hasLength(7), reason: lang.code);
      expect(trDict('wlYearOrdinals', lang.code).split(','), hasLength(10), reason: lang.code);
    }
  });

  test('данные виджета: язык и все подписи', () {
    final payload = widgetLabelsPayload('en');
    expect(payload['wl_lang'], 'en');
    expect(payload['wl_days_many'], 'days');
    expect(payload['wl_in_a_row'], '{w} in a row');
    expect(payload.length, homeWidgetsStrings.length + 1);
  });

  test('каждый ключ, который читает нативный код, есть в словаре', () {
    final known = widgetLabelsPayload('ru').keys.map((k) => k.substring(3)).toSet();
    final used = <String>{};
    final kt = RegExp(r'WidgetText\.(?:get|fmt|plural|list)\(\s*\w+\s*,\s*"([a-z_]+)"');
    final sw = RegExp(r'WidgetText\.(?:get|fmt|plural|list)\(\s*"([a-z_]+)"');
    for (final dir in ['android/app/src/main/kotlin', 'ios/TogetherlyWidget']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.kt') && !f.path.endsWith('.swift')) continue;
        final src = f.readAsStringSync();
        for (final m in [...kt.allMatches(src), ...sw.allMatches(src)]) {
          used.add(m[1]!);
        }
      }
    }
    expect(used, isNotEmpty);
    for (final key in used) {
      final plain = known.contains(key);
      final plural = known.contains('${key}_one');
      expect(plain || plural, isTrue, reason: 'нативный код читает «$key», а в словаре его нет');
    }
  });
}
