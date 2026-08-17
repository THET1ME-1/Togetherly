import 'package:flutter/material.dart';

import 'mood_entry.dart';

/// Половина виджета «Настроение»: что нативная сторона нарисует у человека.
///
/// Сердце заливается по [score], поэтому ноль означает пустой контур — именно
/// так у тестера на iPhone выглядела половина партнёра, хотя в приложении
/// стояло «Оценка 5 из 5» (17.08.2026, связка Android — iOS).
class MoodHalfPayload {
  const MoodHalfPayload({
    this.imagePath = '',
    this.label = '',
    this.score = 0,
    this.colorHex = '',
  });

  final String imagePath;
  final String label;
  final int score;

  /// Цвет в виде `#RRGGBB`; пусто — натив возьмёт свой серый.
  final String colorHex;

  bool get isEmpty => imagePath.isEmpty && label.isEmpty && score == 0;
}

/// Собирает половину виджета из двух источников.
///
/// Главный экран берёт настроение из `MoodService` (записи за сегодня), и когда
/// записи партнёра там нет, в виджет уходил ноль: сердце пустое, подписи нет.
/// При этом на экране «Виджеты» половина партнёра рисуется из `widget_data` и
/// показывает и настроение, и оценку — расхождение человек видит сразу и
/// считает виджет сломанным.
///
/// Правило: свежая запись дня главнее, но если её нет, берём последнее известное
/// настроение из `widget_data`. Оценку и цвет для него восстанавливаем по
/// картинке через [MoodOption]; не нашлась — остаётся подпись, а сердце пустое:
/// врать про оценку хуже, чем не залить сердце.
MoodHalfPayload moodHalfPayload({
  MoodEntry? entry,
  String widgetMoodEmoji = '',
  String widgetMoodLabel = '',
  String gender = '',
}) {
  if (entry != null) {
    return MoodHalfPayload(
      imagePath: entry.imagePath,
      label: entry.localizedLabel,
      score: entry.score,
      colorHex: _hex(entry.color),
    );
  }

  if (widgetMoodEmoji.isEmpty && widgetMoodLabel.isEmpty) {
    return const MoodHalfPayload();
  }

  final option =
      widgetMoodEmoji.isEmpty ? null : MoodOption.byImagePath(widgetMoodEmoji);
  return MoodHalfPayload(
    imagePath: option?.imagePath ?? widgetMoodEmoji,
    label: option?.localizedLabelFor(gender) ??
        (widgetMoodLabel.isNotEmpty ? widgetMoodLabel : ''),
    score: option?.score ?? 0,
    colorHex: option == null ? '' : _hex(option.color),
  );
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
