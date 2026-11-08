import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../dict_strings.dart' show trDict;
import '../l10n/dict/home_widgets.dart';
import 'locale_service.dart';

/// Подписи виджетов рабочего стола на языке приложения.
///
/// Нативная сторона виджетов живёт без Flutter и языка приложения не знает:
/// подписи были зашиты по-русски и оставались русскими у человека с
/// английским приложением (отзыв в App Store 19.08.2026: «The notification
/// and widgets are in Russian though the app I have set to English»).
/// Приложение пишет каждую строку `homeWidgetsStrings` в данные виджетов
/// ключом `wl_<ключ>` (`wlDaysOne` → `wl_days_one`) и код языка `wl_lang` —
/// по нему нативный `WidgetText` выбирает форму множественного числа. Без
/// записи нативный код показывает прежние русские подписи.
class WidgetLabels {
  const WidgetLabels._();

  static bool _listening = false;
  static String? _written;

  /// Записать подписи сейчас и переписывать при смене языка.
  static Future<void> start() async {
    if (!_listening) {
      _listening = true;
      LocaleService.instance.addListener(_onLocale);
    }
    await _write();
  }

  static void _onLocale() => _write();

  static Future<void> _write() async {
    final code = LocaleService.instance.language.code;
    if (_written == code) return;
    _written = code;
    try {
      for (final e in widgetLabelsPayload(code).entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await _redrawAll();
    } catch (e) {
      _written = null;
      debugPrint('WidgetLabels: подписи не записались: $e');
    }
  }

  /// Перерисовать виджеты, чтобы смена языка не ждала следующей синхронизации.
  static Future<void> _redrawAll() async {
    for (final name in kAndroidWidgetProviders) {
      try {
        await HomeWidget.updateWidget(androidName: name);
      } catch (_) {}
    }
    for (final kind in kIosWidgetKinds) {
      try {
        await HomeWidget.updateWidget(iOSName: kind);
      } catch (_) {}
    }
  }
}

/// Что записать в данные виджетов для языка [code].
Map<String, String> widgetLabelsPayload(String code) => {
      'wl_lang': code,
      for (final key in homeWidgetsStrings.keys) widgetLabelDataKey(key): trDict(key, code),
    };

/// `wlDaysOne` → `wl_days_one`.
String widgetLabelDataKey(String dictKey) {
  final body = dictKey.substring(2);
  final snake = body.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
  return 'wl$snake';
}

/// Провайдеры виджетов Android (из AndroidManifest.xml).
const List<String> kAndroidWidgetProviders = [
  'LoveWidgetProvider', 'MoodTilesWidget2x2Provider', 'MoodTilesWidget4x2Provider',
  'CountdownWidget2x2Provider', 'CountdownWidget4x2Provider', 'TogetherWidget2x2Provider',
  'TogetherWidget4x2Provider', 'TogetherWidget4x4Provider', 'PairMapWidget2x2Provider',
  'PairMapWidget4x2Provider', 'PairMapWidget4x4Provider', 'CanvasWidget2x2Provider',
  'CanvasWidget2x3Provider', 'CanvasWidget4x4Provider', 'MascotWidget4x1Provider',
  'MascotWidget2x2Provider', 'MascotWidget4x2Provider', 'MascotWidget4x4Provider',
  'YearRingWidget2x2Provider', 'YearRingWidget4x2Provider', 'YearGridWidget2x2Provider',
  'YearGridWidget4x2Provider', 'NoteWidget2x2Provider', 'NoteWidget4x2Provider',
  'NoteWidget4x4Provider', 'MissWidget2x2Provider', 'MissWidget4x2Provider',
  'MissWidget4x1Provider', 'DaysCounterWidgetProvider', 'StreakWidgetProvider',
  'TimerWidgetProvider', 'PetalTimerWidgetProvider', 'PhotoDayWidgetProvider',
  'SelfPhotoWidgetProvider', 'PartnerPhotoWidgetProvider', 'MoodWidgetProvider',
  'PhotoGridWidgetProvider', 'RelationshipStatsWidgetProvider',
];

/// Виды виджетов iPhone (`kind` в расширении TogetherlyWidget).
const List<String> kIosWidgetKinds = [
  'CanvasWidget', 'CountdownWidget2x2Provider', 'DaysCounterWidgetProvider', 'LockDaysWidget',
  'LockMissWidget', 'LockMoodWidget', 'LoveWidgetProvider', 'MascotWidget',
  'MissWidget4x2Provider', 'MoodTilesWidget2x2Provider', 'MoodWidgetProvider',
  'NoteWidget2x2Provider', 'NoteWidget4x2Provider', 'PairMapWidget', 'PartnerPhotoWidgetProvider',
  'PetalTimerWidgetProvider', 'PhotoDayWidgetProvider', 'PhotoGridWidgetProvider',
  'RelationshipStatsWidgetProvider', 'SelfPhotoWidgetProvider', 'StreakWidgetProvider',
  'TimerWidgetProvider', 'TogetherWidget4x2Provider', 'YearGridWidget4x2Provider',
  'YearRingWidget4x2Provider',
];
