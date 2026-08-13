/// Чем упорядочена лента воспоминаний.
///
/// Дата у записи бывает двух видов: когда событие ПРОИЗОШЛО (её человек
/// ставит сам) и когда запись занесли в приложение. Лента всегда шла по первой,
/// и старая фотография, добавленная сегодня, уезжала в самый низ — «добавьте
/// сортировку по указанной дате» (просьба тестера 13 августа 2026; на деле
/// нужен был выбор).
enum MemorySort {
  /// По дате события — когда это случилось у пары.
  eventDate,

  /// По дате добавления — что занесли последним.
  addedAt,
}

/// Разбор сохранённого выбора. Незнакомое значение — дата события: так лента
/// вела себя всегда.
MemorySort memorySortFromName(String? name) {
  for (final v in MemorySort.values) {
    if (v.name == name) return v;
  }
  return MemorySort.eventDate;
}

/// Сравнение двух воспоминаний, новые сверху.
///
/// У записей, созданных до появления даты добавления, её нет — там берём дату
/// события, иначе вся прежняя лента свалилась бы в конец одной кучей.
int compareMemories(
  MemorySort order, {
  required DateTime aEvent,
  required DateTime bEvent,
  DateTime? aAdded,
  DateTime? bAdded,
}) {
  switch (order) {
    case MemorySort.eventDate:
      return bEvent.compareTo(aEvent);
    case MemorySort.addedAt:
      return (bAdded ?? bEvent).compareTo(aAdded ?? aEvent);
  }
}
