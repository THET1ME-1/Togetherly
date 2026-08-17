import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Самоотчёт о содержимом контейнера виджетов.
///
/// Виджеты на iPhone стоят пустыми в сборках 1.28.9 и 1.29.0, и по снимкам
/// экрана дальше не продвинуться: непонятно, чего именно не хватает — записей в
/// общем контейнере, файлов фото или самого таймлайна. Телефон тестера далеко, и
/// просить открыть диагностический экран, снять кадр и переслать — лишний круг
/// на каждый вопрос.
///
/// Поэтому отчёт уезжает сам, в наш Bugsink, при старте приложения. Человеку
/// достаточно открыть приложение.
///
/// В отчёт НЕ попадают ни тексты, ни ссылки, ни имена: только длина значения и
/// существует ли файл по записанному пути. Этого хватает, чтобы понять, где
/// обрывается цепочка, и не хватает, чтобы прочитать чужую переписку.
class WidgetDiagnostics {
  WidgetDiagnostics._();

  /// Ключи, по которым видно всю цепочку: привязка к паре, тексты половин,
  /// пути к фото и аватарам, данные виджета настроения.
  static const List<String> _keys = [
    'love_widget_group_id',
    'love_widget_partner_uid',
    'my_name',
    'my_status',
    'my_mood',
    'my_photo_path',
    'my_avatar_path',
    'my_mood_emoji_path',
    'partner_name',
    'partner_status',
    'partner_mood',
    'partner_photo_path',
    'partner_avatar_path',
    'partner_mood_emoji_path',
    'mood_latest_group',
    'ios_self_photo_path',
    'ios_partner_photo_path',
    'ios_photo_day_path',
  ];

  /// Собирает сводку: ключ → что с ним. Пусто, есть значение или битый путь.
  static Future<Map<String, String>> collect() async {
    final out = <String, String>{};
    for (final key in _keys) {
      String value = '';
      try {
        value = await HomeWidget.getWidgetData<String>(key) ?? '';
      } catch (e) {
        out[key] = 'ошибка чтения';
        continue;
      }
      if (value.isEmpty) {
        out[key] = 'пусто';
        continue;
      }
      if (key.endsWith('_path')) {
        // Путь без файла — самая частая поломка: запись есть, картинки нет.
        final exists = File(value).existsSync();
        out[key] = exists ? 'файл на месте (${value.length} симв.)' : 'ФАЙЛА НЕТ';
        continue;
      }
      out[key] = 'есть (${value.length} симв.)';
    }
    return out;
  }

  /// Отправляет сводку в Bugsink. Молча выходит на Android: там виджеты живут.
  static Future<void> report({bool onlyIos = true}) async {
    if (onlyIos && !Platform.isIOS) return;
    try {
      final data = await collect();
      await Sentry.captureMessage(
        'widget-diag',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('widget_container', data);
        },
      );
    } catch (_) {
      // Диагностика не смеет мешать запуску.
    }
  }
}
