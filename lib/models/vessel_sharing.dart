import 'memory.dart';
import 'mood_vessel.dart';

/// Что уходит в картинку сосуда, которой пара делится наружу.
///
/// Решает человек — галочками на экране экспорта. Здесь только пересборка
/// кладки под его выбор: снятый вид пропадает из блоков, а высота блока
/// считается заново, иначе по столбику осталось бы видно ровно то, что убрали.

/// Что отмечено, когда экран открывается впервые.
///
/// Настроения, разговоры и воспоминания — то, чем обычно и хвастаются. Цикл и
/// близость сняты: их включает сам человек, если захочет.
const Set<VesselFloor> kDefaultSharedFloors = {
  VesselFloor.mine,
  VesselFloor.partner,
  VesselFloor.chat,
  VesselFloor.memory,
};

/// Кладка под выбранный набор видов.
List<VesselDay> vesselForSharing(
  List<VesselDay> days, {
  required Set<VesselFloor> show,
}) {
  final cycle = show.contains(VesselFloor.cycle) ||
      show.contains(VesselFloor.partnerCycle);
  return [
    for (final d in days)
      VesselDay(
        date: d.date,
        mineMood: show.contains(VesselFloor.mine) ? d.mineMood : null,
        partnerMood: show.contains(VesselFloor.partner) ? d.partnerMood : null,
        chatted: show.contains(VesselFloor.chat) && d.chatted,
        intimacy: show.contains(VesselFloor.intimacy) && d.intimacy,
        period: cycle && d.period,
        partnerPeriod: cycle && d.partnerPeriod,
        memories: show.contains(VesselFloor.memory)
            ? d.memories
            : const <MemoryType>[],
        // floorsOverride намеренно не переносим: у годового блока высота
        // задана явно, и с ней снятые отметки остались бы видны столбиком.
      ),
  ];
}
