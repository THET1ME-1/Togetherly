import 'dart:convert';

import 'gift.dart';

/// Сколько раз партнёру дарили один и тот же подарок.
class GiftTally {
  const GiftTally(this.gift, this.count);

  final Gift gift;
  final int count;

  String get key => gift.key;
}

/// Полка подарков: одинаковые сложены вместе, частые — впереди.
///
/// [records] — записи коллекции `gifts` как есть, с полем `gift_key`.
/// Подарок, которого нет в каталоге (запись от новой версии приложения),
/// пропускается: показать его всё равно нечем.
List<GiftTally> tallyGifts(List<Map<String, dynamic>> records) {
  final counts = <String, int>{};
  for (final r in records) {
    final key = (r['gift_key'] ?? '').toString();
    if (key.isEmpty || GiftCatalog.byKey(key) == null) continue;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final out = counts.entries
      .map((e) => GiftTally(GiftCatalog.byKey(e.key)!, e.value))
      .toList();
  out.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    // при равенстве — порядок каталога, чтобы полка не прыгала между заходами
    return byCount != 0 ? byCount : _catalogIndex(a.key) - _catalogIndex(b.key);
  });
  return out;
}

int _catalogIndex(String key) =>
    GiftCatalog.all.indexWhere((g) => g.key == key);

/// Полученный подарок со всем, что к нему прилагалось.
///
/// Записка, ответ, место и дата встречи живут в самой записи `gifts` и
/// хранятся вечно, но до 1 августа их показывал только лист получения — один
/// раз, в момент вручения. Кто закрыл лист не дочитав, письмо терял: в
/// приложении не было ни одного места, где его можно открыть заново.
class GiftMemo {
  const GiftMemo({
    required this.giftKey,
    this.sentAt,
    this.senderUid = '',
    this.note = '',
    this.reply = '',
    this.place = '',
    this.date,
    this.state = '',
  });

  final String giftKey;

  /// Когда подарок отправлен. null у записей с испорченной датой — такие
  /// встречаются среди мигрированных из Firebase.
  final DateTime? sentAt;

  final String senderUid;

  /// Что вложил даритель.
  final String note;

  /// Что ответил получатель (желание на звезду, согласие на свидание).
  final String reply;

  /// Место встречи — у приглашений.
  final String place;

  /// Дата встречи — у приглашений.
  final DateTime? date;

  final String state;

  /// Есть ли что перечитать. Подарок без единого слова открывать незачем —
  /// на полке он и так виден.
  bool get hasText =>
      note.isNotEmpty || reply.isNotEmpty || place.isNotEmpty || date != null;
}

DateTime? _memoDate(Object? raw) {
  if (raw == null) return null;
  if (raw is num) {
    final ms = raw.toInt();
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  final ms = int.tryParse(s);
  if (ms != null) {
    return ms <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
  return DateTime.tryParse(s)?.toLocal();
}

String _memoText(Object? raw) => (raw ?? '').toString().trim();

GiftMemo _memoOf(Map<String, dynamic> r) => GiftMemo(
      giftKey: (r['gift_key'] ?? '').toString(),
      sentAt: _memoDate(r['created']),
      senderUid: _memoText(r['sender_uid']),
      note: _memoText(r['note']),
      reply: _memoText(r['reply']),
      place: _memoText(r['place']),
      date: _memoDate(r['date']),
      state: _memoText(r['state']),
    );

/// Все полученные подарки одного вида — свежие сверху.
///
/// Записи без даты уходят вниз: у мигрированных из Firebase `created` бывает
/// пустым, и ронять из-за них порядок остальных незачем.
List<GiftMemo> memosOfKey(List<Map<String, dynamic>> records, String key) {
  final out = records
      .where((r) => (r['gift_key'] ?? '').toString() == key)
      .map(_memoOf)
      .toList();
  out.sort((a, b) {
    final ad = a.sentAt, bd = b.sentAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return out;
}

/// Сколько подарков на полке хранят слова — по этому числу профиль решает,
/// подсказывать ли, что полку можно открыть.
int countWithText(List<Map<String, dynamic>> records) =>
    records.map(_memoOf).where((m) => m.hasText).length;

/// «Я скучаю» в разрезе дней недели.
class WeekStats {
  const WeekStats(this.byDay);

  /// Семь чисел, начиная с понедельника.
  final List<int> byDay;

  int get total => byDay.fold(0, (s, v) => s + v);

  bool get isEmpty => total == 0;

  /// День недели с максимумом (1 = понедельник). При равенстве — более ранний.
  /// null, если истории ещё нет.
  int? get topDay {
    if (isEmpty) return null;
    var best = 0;
    for (var i = 1; i < byDay.length; i++) {
      if (byDay[i] > byDay[best]) best = i;
    }
    return best + 1;
  }
}

/// Разбирает поле `by_weekday` записи `miss_you`: карта «день → количество».
///
/// История копится с релиза: у пар, заведённых раньше, поле пустое, и экран
/// честно показывает, что данных пока нет.
WeekStats parseWeekdays(String? raw) {
  final days = List<int>.filled(7, 0);
  if (raw == null || raw.trim().isEmpty) return WeekStats(days);
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      decoded.forEach((k, v) {
        final day = int.tryParse(k.toString());
        final count = v is num ? v.toInt() : int.tryParse(v.toString());
        if (day == null || count == null || day < 1 || day > 7) return;
        days[day - 1] = count;
      });
    }
  } catch (_) {
    return WeekStats(List<int>.filled(7, 0));
  }
  return WeekStats(days);
}
