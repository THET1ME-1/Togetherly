import 'dart:convert';

/// Запись коллекции `miss_you` — по одной на каждого в паре.
///
/// Кроме счётчика сервер копит `by_weekday` (карта «день недели → сколько раз»,
/// см. роут `/api/group/miss-you`) и держит последний импульс с его временем.
/// Экрану этого хватает: истории отдельной коллекцией пока нет.
class MissYouEntry {
  final String uid;
  final int count;

  /// `miss_you`, `thinking_of_you`, `want_hug` или `custom`.
  final String lastVibe;

  /// Текст своего пожелания — пусто у трёх встроенных вайбов.
  final String lastVibeText;

  /// Когда импульс ушёл. Пусто, если сервер время не прислал: выдумывать
  /// «сегодня» нельзя, подпись под этим временем врала бы.
  final DateTime? updatedAt;

  /// Дни недели 1 (понедельник) … 7 (воскресенье) → сколько импульсов.
  final Map<int, int> byWeekday;

  /// Тип импульса (`miss_you`, `thinking_of_you`, `want_hug`, `custom`) →
  /// сколько раз его отправили. Копит тот же роут `/api/group/miss-you`.
  final Map<String, int> byVibe;

  const MissYouEntry({
    required this.uid,
    this.count = 0,
    this.lastVibe = '',
    this.lastVibeText = '',
    this.updatedAt,
    this.byWeekday = const {},
    this.byVibe = const {},
  });

  factory MissYouEntry.fromRow(Map<String, dynamic> row) {
    final rawTime = (row['updated_at'] ?? '').toString();
    final count = (row['count'] as num?)?.toInt() ?? 0;
    return MissYouEntry(
      uid: (row['user_uid'] ?? '').toString(),
      count: count,
      lastVibe: (row['last_vibe'] ?? '').toString(),
      lastVibeText: (row['last_vibe_text'] ?? '').toString(),
      updatedAt: rawTime.isEmpty ? null : DateTime.tryParse(rawTime),
      byWeekday: parseByWeekday(row['by_weekday']),
      byVibe: parseByVibe(row['by_vibe'], total: count),
    );
  }
}

/// Карта дней приезжает СТРОКОЙ с json внутри (поле text, не json), поэтому
/// разбирается вручную. Ключи бывают и числами, и строками, а значения —
/// строками: хук пишет их через `JSON.stringify` по накопленному объекту.
Map<int, int> parseByWeekday(Object? raw) {
  if (raw == null) return const {};
  Object? decoded = raw;
  if (raw is String) {
    if (raw.trim().isEmpty) return const {};
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const {};
    }
  }
  if (decoded is! Map) return const {};
  final out = <int, int>{};
  decoded.forEach((k, v) {
    final day = k is int ? k : int.tryParse(k.toString());
    final n = v is num ? v.toInt() : int.tryParse(v.toString());
    if (day == null || n == null) return;
    if (day < 1 || day > 7) return;
    out[day] = n;
  });
  return out;
}

/// Разбор карты «импульс → сколько раз». Приезжает такой же строкой с json
/// внутри, как и карта дней.
///
/// Пустая карта у записи с непустым счётчиком означает не ноль, а «этих чисел
/// сервер ещё не копил»: до 13 августа 2026 любой импульс шёл в общий счётчик
/// без разбора. Такой записи весь накопленный счёт отдаём «скучаю» — иначе у
/// пары с четырьмя сотнями импульсов все строки показали бы нули.
Map<String, int> parseByVibe(Object? raw, {int total = 0}) {
  Object? decoded = raw;
  if (raw is String) {
    if (raw.trim().isEmpty) {
      decoded = null;
    } else {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        decoded = null;
      }
    }
  }
  final out = <String, int>{};
  if (decoded is Map) {
    decoded.forEach((k, v) {
      final key = k.toString();
      final n = v is num ? v.toInt() : int.tryParse(v.toString());
      if (key.isEmpty || n == null || n <= 0) return;
      out[key] = n;
    });
  }
  if (out.isEmpty && total > 0) return {'miss_you': total};
  return out;
}

/// Состояние пары: своя запись и партнёрская.
class MissYouState {
  final MissYouEntry? mine;
  final MissYouEntry? partner;

  const MissYouState({this.mine, this.partner});

  static const empty = MissYouState();

  int get myCount => mine?.count ?? 0;
  int get partnerCount => partner?.count ?? 0;

  /// Партнёром считается ПЕРВАЯ чужая запись. Третьего в паре быть не может,
  /// но мусор от прошлых связей в группе иногда лежит.
  factory MissYouState.fromRows(
    List<Map<String, dynamic>> rows, {
    required String myUid,
  }) {
    MissYouEntry? mine;
    MissYouEntry? partner;
    for (final row in rows) {
      final e = MissYouEntry.fromRow(row);
      if (e.uid == myUid) {
        mine ??= e;
      } else {
        partner ??= e;
      }
    }
    return MissYouState(mine: mine, partner: partner);
  }
}

/// Столбик одного дня недели: сами числа и доли для рисования.
class WeekBar {
  final int weekday;
  final int mine;
  final int partner;
  final double mineFraction;
  final double partnerFraction;

  const WeekBar({
    required this.weekday,
    required this.mine,
    required this.partner,
    required this.mineFraction,
    required this.partnerFraction,
  });
}

/// Семь столбиков с понедельника. Шкала ОБЩАЯ на обоих: иначе один импульс
/// партнёра рисовался бы вровень с сотней своих.
List<WeekBar> weekBars(Map<int, int> mine, Map<int, int> partner) {
  var max = 0;
  for (var d = 1; d <= 7; d++) {
    final a = mine[d] ?? 0;
    final b = partner[d] ?? 0;
    if (a > max) max = a;
    if (b > max) max = b;
  }
  return [
    for (var d = 1; d <= 7; d++)
      WeekBar(
        weekday: d,
        mine: mine[d] ?? 0,
        partner: partner[d] ?? 0,
        mineFraction: max == 0 ? 0 : (mine[d] ?? 0) / max,
        partnerFraction: max == 0 ? 0 : (partner[d] ?? 0) / max,
      ),
  ];
}

bool weekBarsAreEmpty(List<WeekBar> bars) =>
    bars.every((b) => b.mine == 0 && b.partner == 0);
