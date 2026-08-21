import 'package:flutter/services.dart';

import '../utils/safe_text.dart';
import 'memory.dart';

/// Прикрепление воспоминания к сообщению: «собачка» в чате.
///
/// Правила вынесены из экрана, потому что на них держится сам факт того, что
/// кнопка отвечает на нажатие: пока панель показывалась только при непустом
/// списке, любая заминка с загрузкой записей выглядела как сломанная кнопка.

/// Сколько подсказок помещается над полем ввода, не закрывая переписку.
const int kMentionLimit = 6;

/// Записи, подходящие под запрос после «собачки».
List<Memory> mentionMatches(
  List<Memory> pins,
  String query, {
  int limit = kMentionLimit,
}) {
  final q = query.trim().toLowerCase();
  final out = <Memory>[];
  for (final m in pins) {
    if (q.isNotEmpty && !mentionLabel(m).toLowerCase().contains(q)) continue;
    out.add(m);
    if (out.length == limit) break;
  }
  return out;
}

/// Чем запись подписана в списке и в чипе прикреплённого пина.
///
/// Название, подпись, место, песня — что нашлось первым. У половины записей
/// названия нет вовсе, и без этой лесенки в списке стояли бы одни «Фото».
String mentionLabel(Memory m) {
  final title = (m.title ?? '').trim();
  if (title.isNotEmpty) return title;
  final caption = (m.caption ?? '').trim();
  if (caption.isNotEmpty) return caption.truncateGraphemes(30, ellipsis: '…');
  final loc = (m.locationName ?? '').trim();
  if (loc.isNotEmpty) return loc;
  final music = (m.musicTitle ?? '').trim();
  if (music.isNotEmpty) return music;
  return m.typeLabel;
}

/// Видна ли панель подсказок.
///
/// Видна ВСЕГДА, пока идёт набор после «собачки» — даже когда показывать
/// нечего. Человек нажал кнопку и обязан увидеть ответ: пустая панель со
/// строкой «пока нечего прикрепить» честнее, чем тишина, которую читают как
/// поломку.
bool mentionPanelVisible(String? query) => query != null;

/// Что должно оказаться в поле ввода после нажатия на «собачку».
///
/// Отдаём текст и курсор ОДНИМ значением: `controller.text = …` с последующим
/// `controller.selection = …` — это две отправки в клавиатуру, и первая уходит
/// с курсором −1. iOS на такое отвечает своим состоянием поля, и вставленный
/// символ откатывается вместе с открытой панелью подсказок.
TextEditingValue mentionTriggerValue(String text) {
  final next = text.endsWith('@')
      ? text
      : (text.isEmpty || text.endsWith(' ') ? '$text@' : '$text @');
  return TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: next.length),
  );
}
