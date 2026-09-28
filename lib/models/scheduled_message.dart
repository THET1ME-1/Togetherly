/// Отложенное сообщение (28.09.2026): долгое нажатие на «отправить»
/// открывает календарь и часы, сообщение придёт партнёру в выбранный момент.
/// Придерживает и выпускает его сервер (`deliver_at`, `_deliver_worker` в
/// hotpath), поэтому оно дойдёт и при закрытом приложении автора.

/// Как далеко вперёд можно отложить.
const Duration kScheduleMaxAhead = Duration(days: 365);

/// Придержано ли сообщение прямо сейчас (для своей стороны).
bool isHeld(int? deliverAt, {DateTime? now}) =>
    (deliverAt ?? 0) > (now ?? DateTime.now()).millisecondsSinceEpoch;

/// Момент из выбранных даты и времени; null — он уже прошёл.
DateTime? scheduledMoment(DateTime date, int hour, int minute, {DateTime? now}) {
  final at = DateTime(date.year, date.month, date.day, hour, minute);
  return at.isAfter(now ?? DateTime.now()) ? at : null;
}
