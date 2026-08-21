import 'dart:ui';

import 'cycle_entry.dart';

/// Сосуд месяца: день — блок, который падает сверху и ложится в кладку.
///
/// Календарь отвечает на вопрос «какое было настроение», сосуд — «сколько нас
/// было друг у друга». Поэтому высота блока считается по СОБЫТИЯМ дня, а цвет
/// берётся у настроения.
///
/// Два правила, которые нельзя менять молча:
///
/// * месячные высоту блока НЕ меняют. Иначе по кладке стало бы видно то, о чём
///   человек не просил рассказывать; это состояние, а не событие, и рисуется
///   тонкой кромкой;
/// * близость — обычный этаж. У такой отметки `shared` поднят самим сервисом,
///   её видят оба, и прятать её незачем.
enum VesselWho { none, mine, partner, both }

/// Из чего сложен блок. Виджет рисует значок по этому списку, а не собирает
/// свой: разъехавшись, счёт этажей и картинка показывали бы разное.
enum VesselFloor { mine, partner, intimacy, memory, chat }

class VesselDay {
  const VesselDay({
    required this.date,
    this.mineMood,
    this.partnerMood,
    this.intimacy = false,
    this.period = false,
    this.partnerPeriod = false,
    this.memories = 0,
    this.chatted = false,
    this.floorsOverride,
  });

  final DateTime date;

  /// Цвет отметки настроения — свой и партнёра. `null` — не отмечался.
  final Color? mineMood;
  final Color? partnerMood;

  final bool intimacy;

  /// Месячные — своя отметка и партнёрская. Разведены, потому что кромки у них
  /// разного цвета: в паре из двух девушек иначе не понять, чья это полоса.
  final bool period;
  final bool partnerPeriod;

  /// Сколько воспоминаний легло в ленту в этот день.
  ///
  /// Сосуд отвечает на вопрос «сколько нас было друг у друга», и совместный
  /// вечер, с которого осталось пять снимков, — это про «нас» не меньше, чем
  /// отметка настроения. Но и башню из одного дня строить нельзя: у пары
  /// бывает пятнадцать кадров с прогулки, а блок должен оставаться блоком.
  final int memories;

  /// Был ли в этот день разговор в чате.
  ///
  /// Считаем фактом, а не числом сообщений: триста реплик за вечер — это один
  /// разговор, и мерить его высотой значило бы, что молчаливая пара живёт хуже.
  final bool chatted;

  /// Явная высота блока. Нужна годовому виду, где блок — это месяц целиком.
  final int? floorsOverride;

  /// Этажи блока снизу вверх: своё настроение, настроение партнёра, разговор,
  /// воспоминания, близость сверху.
  List<VesselFloor> get floorKinds => [
        if (mineMood != null) VesselFloor.mine,
        if (partnerMood != null) VesselFloor.partner,
        if (chatted) VesselFloor.chat,
        for (var i = 0; i < _memoryFloors; i++) VesselFloor.memory,
        if (intimacy) VesselFloor.intimacy,
      ];

  /// Сколько этажей в блоке. Ноль — дня в кладке нет вовсе.
  int get floors => floorsOverride ?? floorKinds.length;

  /// Воспоминания дают не больше двух этажей: один за «сегодня что-то
  /// сохранили», второй — за день, о котором осталась целая пачка.
  int get _memoryFloors => memories >= 3 ? 2 : (memories > 0 ? 1 : 0);

  bool get isEmpty => floors == 0;

  VesselWho get who {
    if (mineMood != null && partnerMood != null) return VesselWho.both;
    if (mineMood != null) return VesselWho.mine;
    if (partnerMood != null) return VesselWho.partner;
    return VesselWho.none;
  }
}

/// Блок в кладке: чей столбец и на какой высоте лежит.
class VesselBlock {
  const VesselBlock({
    required this.day,
    required this.column,
    required this.bottom,
  });

  final VesselDay day;
  final int column;

  /// Сколько этажей под ним в этом столбце.
  final int bottom;

  DateTime get date => day.date;
  int get floors => day.floors;
}

/// Раскладка кладки: блок падает туда, где ниже всего, — как в тетрисе.
///
/// Порядок дней сохраняется: сначала падает первое число, потом второе.
List<VesselBlock> layoutVessel(List<VesselDay> days, {required int columns}) {
  final heights = List<int>.filled(columns, 0);
  final out = <VesselBlock>[];
  for (final day in days) {
    if (day.isEmpty) continue;
    var col = 0;
    for (var c = 1; c < columns; c++) {
      if (heights[c] < heights[col]) col = c;
    }
    out.add(VesselBlock(day: day, column: col, bottom: heights[col]));
    heights[col] += day.floors;
  }
  return out;
}

/// Сколько дней месяц потерял: их в кладке нет, и это видно щербинами.
int vesselGaps(List<VesselDay> days) => days.where((d) => d.isEmpty).length;

/// Высота кладки в этажах — по самому высокому столбцу.
int vesselHeight(List<VesselBlock> blocks) {
  var top = 0;
  for (final b in blocks) {
    final h = b.bottom + b.floors;
    if (h > top) top = h;
  }
  return top;
}

/// Дни месяца — обёртка над [buildVesselRange] для тех, кому нужен ровно месяц.
List<VesselDay> buildVesselDays({
  required DateTime month,
  required Map<String, Color> mineMoods,
  required Map<String, Color> partnerMoods,
  required List<CycleEntry> myCycle,
  required List<CycleEntry> partnerCycle,
  Map<String, int> memories = const {},
  Set<String> chatDays = const {},
}) =>
    buildVesselRange(
      from: DateTime(month.year, month.month),
      to: DateTime(month.year, month.month + 1, 0),
      mineMoods: mineMoods,
      partnerMoods: partnerMoods,
      myCycle: myCycle,
      partnerCycle: partnerCycle,
      memories: memories,
      chatDays: chatDays,
    );

/// Дни любого отрезка, собранные из отметок настроения, цикла, ленты и чата.
///
/// Отрезком, а не месяцем: сосуд показывают и за неделю, и за месяц — раньше
/// он молча рисовал месяц, какой бы период ни выбрал человек.
///
/// Отметки цикла приходят уже отфильтрованными сервером: чужие записи без
/// `shared` до устройства не доезжают вовсе, поэтому здесь их не проверяем.
List<VesselDay> buildVesselRange({
  required DateTime from,
  required DateTime to,
  required Map<String, Color> mineMoods,
  required Map<String, Color> partnerMoods,
  required List<CycleEntry> myCycle,
  required List<CycleEntry> partnerCycle,
  Map<String, int> memories = const {},
  Set<String> chatDays = const {},
}) {
  final periods = <String>{};
  final partnerPeriods = <String>{};
  final intimacy = <String>{};
  for (final e in myCycle) {
    final key = vesselDayKey(e.day);
    if (e.kind == CycleKind.period) periods.add(key);
    if (e.kind == CycleKind.intimacy) intimacy.add(key);
  }
  for (final e in partnerCycle) {
    final key = vesselDayKey(e.day);
    if (e.kind == CycleKind.period) partnerPeriods.add(key);
    // Близость — общая отметка пары: сервер отдаёт её обоим, и в кладке она
    // одна, чьей бы рукой ни была поставлена.
    if (e.kind == CycleKind.intimacy) intimacy.add(key);
  }

  final first = DateTime(from.year, from.month, from.day);
  final last = DateTime(to.year, to.month, to.day);
  final out = <VesselDay>[];
  for (var date = first;
      !date.isAfter(last);
      date = DateTime(date.year, date.month, date.day + 1)) {
    final key = vesselDayKey(date);
    out.add(VesselDay(
      date: date,
      mineMood: mineMoods[key],
      partnerMood: partnerMoods[key],
      intimacy: intimacy.contains(key),
      period: periods.contains(key),
      partnerPeriod: partnerPeriods.contains(key),
      memories: memories[key] ?? 0,
      chatted: chatDays.contains(key),
    ));
  }
  return out;
}

/// Год кладут месяцами, а не днями: 365 блоков в сосуд не поместятся, а
/// разглядывать их всё равно нечем. Высота месяца — сколько в нём было живых
/// дней, поделённое на три: иначе один плотный месяц упирается в крышку.
List<VesselDay> buildVesselYear({
  required int year,
  required Map<String, Color> mineMoods,
  required Map<String, Color> partnerMoods,
  required List<CycleEntry> myCycle,
  required List<CycleEntry> partnerCycle,
  Map<String, int> memories = const {},
  Set<String> chatDays = const {},
}) {
  final out = <VesselDay>[];
  for (var m = 1; m <= 12; m++) {
    final days = buildVesselRange(
      from: DateTime(year, m),
      to: DateTime(year, m + 1, 0),
      mineMoods: mineMoods,
      partnerMoods: partnerMoods,
      myCycle: myCycle,
      partnerCycle: partnerCycle,
      memories: memories,
      chatDays: chatDays,
    );
    final alive = days.where((d) => !d.isEmpty).toList();
    final mine = alive.where((d) => d.mineMood != null).length;
    final theirs = alive.where((d) => d.partnerMood != null).length;
    out.add(VesselDay(
      date: DateTime(year, m),
      // Цвет месяца — от самого частого настроения в нём: блок должен читаться
      // так же, как дневной, а не быть серой колонкой.
      mineMood: mine > 0 ? _commonColor(alive.map((d) => d.mineMood)) : null,
      partnerMood:
          theirs > 0 ? _commonColor(alive.map((d) => d.partnerMood)) : null,
      intimacy: alive.any((d) => d.intimacy),
      period: alive.any((d) => d.period),
      partnerPeriod: alive.any((d) => d.partnerPeriod),
      memories: days.fold(0, (sum, d) => sum + d.memories),
      chatted: alive.any((d) => d.chatted),
      floorsOverride: alive.isEmpty ? 0 : (alive.length / 3).ceil(),
    ));
  }
  return out;
}

Color? _commonColor(Iterable<Color?> colors) {
  final counts = <Color, int>{};
  for (final c in colors) {
    if (c == null) continue;
    counts[c] = (counts[c] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  var best = counts.keys.first;
  for (final e in counts.entries) {
    if (e.value > counts[best]!) best = e.key;
  }
  return best;
}

/// Ключ дня — тот же формат, что у отметок настроения (`MoodEntry.dayKey`).
String vesselDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
