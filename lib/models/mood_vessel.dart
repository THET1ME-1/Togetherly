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

class VesselDay {
  const VesselDay({
    required this.date,
    this.mineMood,
    this.partnerMood,
    this.intimacy = false,
    this.period = false,
    this.partnerPeriod = false,
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

  /// Сколько этажей в блоке. Ноль — дня в кладке нет вовсе.
  int get floors =>
      (mineMood != null ? 1 : 0) +
      (partnerMood != null ? 1 : 0) +
      (intimacy ? 1 : 0);

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

/// Дни месяца, собранные из отметок настроения и календаря цикла.
///
/// Отметки цикла приходят уже отфильтрованными сервером: чужие записи без
/// `shared` до устройства не доезжают вовсе, поэтому здесь их не проверяем.
List<VesselDay> buildVesselDays({
  required DateTime month,
  required Map<String, Color> mineMoods,
  required Map<String, Color> partnerMoods,
  required List<CycleEntry> myCycle,
  required List<CycleEntry> partnerCycle,
}) {
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
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

  return [
    for (var d = 1; d <= lastDay; d++)
      () {
        final date = DateTime(month.year, month.month, d);
        final key = vesselDayKey(date);
        return VesselDay(
          date: date,
          mineMood: mineMoods[key],
          partnerMood: partnerMoods[key],
          intimacy: intimacy.contains(key),
          period: periods.contains(key),
          partnerPeriod: partnerPeriods.contains(key),
        );
      }(),
  ];
}

/// Ключ дня — тот же формат, что у отметок настроения (`MoodEntry.dayKey`).
String vesselDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
