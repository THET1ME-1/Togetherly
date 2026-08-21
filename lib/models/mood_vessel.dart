import 'dart:ui';

import 'cycle_entry.dart';
import 'memory.dart';

/// Сосуд месяца: день — блок, который падает сверху и ложится в кладку.
///
/// Календарь отвечает на вопрос «какое было настроение», сосуд — «сколько нас
/// было друг у друга». Поэтому высота блока считается по СОБЫТИЯМ дня, а цвет
/// берётся у настроения.
///
/// Что кладётся этажом: настроение своё и партнёра, месячные обоих, разговор,
/// воспоминания по видам и близость сверху. Близость и месячные показываются
/// потому, что и то и другое уже стоит в календаре рядом — сосуд не открывает
/// ничего, чего человек не видел бы на соседнем экране, а отметки партнёрши
/// доезжают до устройства только с её разрешения.
enum VesselWho { none, mine, partner, both }

/// Из чего сложен блок. Виджет рисует значок по этому списку, а не собирает
/// свой: разъехавшись, счёт этажей и картинка показывали бы разное.
enum VesselFloor { mine, partner, cycle, partnerCycle, chat, memory, intimacy }

/// Этаж блока: вид и, у воспоминания, его вид записи.
///
/// Фотография, песня и заметка — разные вечера, и значок обязан их различать:
/// одним фотоаппаратом на всё выходило, будто пара весь месяц только
/// фотографировала.
class VesselFloorSpec {
  const VesselFloorSpec(this.kind, {this.memoryType});

  final VesselFloor kind;
  final MemoryType? memoryType;
}

class VesselDay {
  const VesselDay({
    required this.date,
    this.mineMood,
    this.partnerMood,
    this.intimacy = false,
    this.period = false,
    this.partnerPeriod = false,
    this.memories = const [],
    this.chatted = false,
    this.floorsOverride,
  });

  final DateTime date;

  /// Цвет отметки настроения — свой и партнёра. `null` — не отмечался.
  final Color? mineMood;
  final Color? partnerMood;

  final bool intimacy;

  /// Месячные — своя отметка и партнёрская. Разведены, потому что цвета у них
  /// разные: в паре из двух девушек иначе не понять, чей это этаж.
  final bool period;
  final bool partnerPeriod;

  /// Какие записи легли в ленту в этот день, в порядке появления.
  ///
  /// Считаем ВИДЫ, а не штуки: пятнадцать кадров с прогулки — это один вечер,
  /// и башня из них врала бы про день сильнее, чем один этаж. Зато вечер, где
  /// была и песня, и заметка, и место, поднимет блок на три.
  final List<MemoryType> memories;

  /// Был ли в этот день разговор в чате.
  ///
  /// Считаем фактом, а не числом сообщений: триста реплик за вечер — это один
  /// разговор, и мерить его высотой значило бы, что молчаливая пара живёт хуже.
  final bool chatted;

  /// Явная высота блока. Нужна годовому виду, где блок — это месяц целиком.
  final int? floorsOverride;

  /// Этажи блока снизу вверх: настроения, месячные, разговор, воспоминания по
  /// видам, близость сверху.
  List<VesselFloorSpec> get floorKinds => [
        if (mineMood != null) const VesselFloorSpec(VesselFloor.mine),
        if (partnerMood != null) const VesselFloorSpec(VesselFloor.partner),
        if (period) const VesselFloorSpec(VesselFloor.cycle),
        if (partnerPeriod) const VesselFloorSpec(VesselFloor.partnerCycle),
        if (chatted) const VesselFloorSpec(VesselFloor.chat),
        for (final t in memoryKinds) VesselFloorSpec(VesselFloor.memory, memoryType: t),
        if (intimacy) const VesselFloorSpec(VesselFloor.intimacy),
      ];

  /// Сколько этажей в блоке. Ноль — дня в кладке нет вовсе.
  int get floors => floorsOverride ?? floorKinds.length;

  /// Виды записей за день, по одному разу и не больше четырёх.
  ///
  /// Предел нужен году: там в блок сходится целый месяц, и все восемь видов
  /// подряд выгнали бы одну колонку под самую крышку, а соседние оставили
  /// плинтусом.
  List<MemoryType> get memoryKinds {
    final seen = <MemoryType>[];
    for (final t in memories) {
      if (seen.contains(t)) continue;
      seen.add(t);
      if (seen.length == 4) break;
    }
    return seen;
  }

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
  Map<String, List<MemoryType>> memories = const {},
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
  Map<String, List<MemoryType>> memories = const {},
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
      memories: memories[key] ?? const [],
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
  Map<String, List<MemoryType>> memories = const {},
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
      // Месяц наследует ВИДЫ записей, а не их число: блок года и так стоит на
      // своей высоте (`floorsOverride`), а значки говорят, чем месяц был занят.
      memories: [for (final d in days) ...d.memories],
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
