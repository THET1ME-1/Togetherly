/// Один импульс «Скучаю» из истории пары (`miss_you_events` в hotpath).
///
/// Запись `miss_you` держит только счётчик и последний импульс; история
/// хранит каждый, частые тапы одного и того же склеены в [count].
class MissYouEvent {
  const MissYouEvent({
    required this.id,
    required this.uid,
    required this.vibe,
    required this.at,
    this.text = '',
    this.count = 1,
    this.replyTo,
  });

  final String id;
  final String uid;

  /// `miss_you`, `thinking_of_you`, `want_hug` или `custom` (тогда [text]).
  final String vibe;
  final String text;
  final int count;

  /// Id импульса, на который это ответ.
  final String? replyTo;
  final DateTime at;

  static MissYouEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}';
    final uid = '${raw['uid'] ?? ''}';
    final at = raw['at'];
    if (id.isEmpty || uid.isEmpty || at is! num) return null;
    final reply = '${raw['replyTo'] ?? ''}';
    return MissYouEvent(
      id: id,
      uid: uid,
      vibe: '${raw['vibe'] ?? 'miss_you'}',
      text: '${raw['text'] ?? ''}',
      count: ((raw['count'] as num?)?.toInt() ?? 1).clamp(1, 9999),
      replyTo: reply.isEmpty ? null : reply,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
    );
  }

  static List<MissYouEvent> parseList(Object? raw) => [
        if (raw is List)
          for (final r in raw) ?fromJson(r),
      ]..sort((a, b) => b.at.compareTo(a.at));
}

/// Что показать на экране: импульсы сегодняшнего дня по часам телефона, а если
/// сегодня пусто — вчерашние (чтобы утром было видно, что пришло ночью).
/// `yesterday` — показан ли вчерашний день.
({List<MissYouEvent> events, bool yesterday}) missYouDay(List<MissYouEvent> all, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final yday = today.subtract(const Duration(days: 1));
  final t = [for (final e in all) if (!e.at.isBefore(today)) e];
  if (t.isNotEmpty) return (events: t, yesterday: false);
  final y = [for (final e in all) if (!e.at.isBefore(yday) && e.at.isBefore(today)) e];
  return (events: y, yesterday: y.isNotEmpty);
}

/// Импульсы партнёра, на которые я уже ответил.
Set<String> missYouReplied(List<MissYouEvent> all, String myUid) => {
      for (final e in all)
        if (e.uid == myUid && e.replyTo != null) e.replyTo!,
    };

/// Чем отвечать на импульс: тем же, кроме своего пожелания партнёра — оно про
/// него, эхом его не возвращают, на него уходит «скучаю».
String missYouReplyVibe(String vibe) =>
    (vibe == 'thinking_of_you' || vibe == 'want_hug') ? vibe : 'miss_you';

/// Полночь телефона в мс — с неё сервер отдаёт историю (вчера тоже нужно).
int missYouHistorySince(DateTime now) =>
    DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)).millisecondsSinceEpoch;
