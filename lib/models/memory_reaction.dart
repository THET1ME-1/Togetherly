import 'package:flutter/material.dart';

/// Значок реакции на воспоминание.
///
/// Реакция в паре именная: людей двое, поэтому счётчика «12 лайков» тут не
/// бывает — рядом с записью стоит аватарка того, кто отметил, и его значок.
class MemoryReaction {
  const MemoryReaction(this.key, this.icon, this.dictKey);

  /// Что лежит в записи: короткий ключ, а не кодпоинт значка.
  final String key;

  final IconData icon;

  /// Ключ подписи в словаре — для доступности и листа выбора.
  final String dictKey;
}

/// Набор значков. Сердце первое: им отмечают чаще всего, и оно же стоит
/// на кнопке в тулбаре открытого пина.
const List<MemoryReaction> kMemoryReactions = [
  MemoryReaction('heart', Icons.favorite_rounded, 'reactionHeart'),
  MemoryReaction('mood', Icons.mood_rounded, 'reactionMood'),
  MemoryReaction('wow', Icons.sentiment_very_satisfied_rounded, 'reactionWow'),
  MemoryReaction('fire', Icons.local_fire_department_rounded, 'reactionFire'),
  MemoryReaction('cry', Icons.sentiment_very_dissatisfied_rounded, 'reactionCry'),
  MemoryReaction('star', Icons.auto_awesome_rounded, 'reactionStar'),
];

/// Значок по ключу. Незнакомый ключ (запись из будущей версии) откатывается
/// на сердце — показать что-то лучше, чем потерять чужую отметку.
MemoryReaction reactionByKey(String key) {
  for (final r in kMemoryReactions) {
    if (r.key == key) return r;
  }
  return kMemoryReactions.first;
}

/// Разбор карты реакций из json-поля записи: `uid → ключ значка`.
///
/// Всё незнакомое выбрасывается молча: запись важнее отметки, и чужая
/// версия приложения не должна ронять ленту.
Map<String, String> parseReactions(dynamic raw) {
  if (raw is! Map) return {};
  final known = {for (final r in kMemoryReactions) r.key};
  final out = <String, String>{};
  raw.forEach((k, v) {
    final uid = k.toString();
    final key = v?.toString() ?? '';
    if (uid.isEmpty || key.isEmpty) return;
    if (!known.contains(key)) return;
    out[uid] = key;
  });
  return out;
}

/// Новая карта реакций после нажатия.
///
/// Реакция у человека одна: тот же значок снимает отметку, другой —
/// заменяет прежний. Чужие отметки не трогаются.
Map<String, String> withReaction(
  Map<String, String> current,
  String uid,
  String key,
) {
  final out = Map<String, String>.from(current);
  if (uid.isEmpty) return out;
  if (key.isEmpty || out[uid] == key) {
    out.remove(uid);
    return out;
  }
  out[uid] = key;
  return out;
}
