import '../dict_strings.dart';
import '../services/locale_service.dart';

/// Даты в подписях виджетов на языке приложения.
///
/// Подписи «С 1 ноября 2025» собирались из своего русского списка месяцев,
/// и английское приложение показывало дату начала пары по-русски (отзыв
/// 23.11.2026: «текст иногда появляется на белорусском, хотя стоит английский»).

/// «1 ноября 2025», «November 1, 2025», «2025年11月1日».
String widgetDateLong(DateTime day) {
  final strings = LocaleService.current;
  return switch (LocaleService.instance.language) {
    AppLanguage.zh => '${day.year}年${strings.dayLogDate(day)}',
    AppLanguage.en => '${strings.dayLogDate(day)}, ${day.year}',
    _ => '${strings.dayLogDate(day)} ${day.year}',
  };
}

/// «1 ноября», «November 1» — без года, для строки годовщины.
String widgetDateShort(DateTime day) => LocaleService.current.dayLogDate(day);

/// «С 1 ноября 2025», «Since November 1, 2025».
String widgetSinceLong(DateTime day) => _capitalized(widgetSince(widgetDateLong(day)));

/// «с 01.11.2025», «since 01.11.2025» — подпись с уже готовой датой.
String widgetSince(String date) => trKey('wlSince').replaceAll('{date}', date);

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
