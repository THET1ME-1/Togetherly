/// Счётчик, который показывает тап раньше, чем ответил сервер.
///
/// Заведён по жалобе тестера на «Скучаю»: «тыкаешь, а оно то пересчитывает, то
/// наоборот уменьшает, само меняет число, когда хочет». Прежняя кнопка держала
/// надбавку целым числом `_inFlightTaps` и снимала её ТОЛЬКО положительной
/// дельтой живого снимка. Отсюда два расхождения:
///
/// * отправка провалилась (таймаут, 429, отказ роута — `incrementMissYou`
///   возвращает false молча), а надбавка осталась висеть навсегда;
/// * подписка отвалилась и переподнялась тем же числом — дельта ноль, надбавка
///   снова живёт, и следующий импульс партнёра снимает чужой тап.
///
/// Здесь каждое ожидание помнит свой момент: подтверждение снимает столько
/// ожиданий, на сколько вырос серверный счётчик, отказ снимает одно сразу, а
/// протухшее ожидание уходит само — число садится на серверную правду вместо
/// того, чтобы жить своей жизнью.
class OptimisticCount {
  /// Сколько подтвердил сервер.
  final int confirmed;

  /// Моменты тапов, которых сервер ещё не подтвердил.
  final List<DateTime> _pending;

  /// Сколько живёт неподтверждённый тап. Дольше держать нечестно: за десять
  /// секунд событие либо доехало, либо не доедет вовсе.
  static const Duration ttl = Duration(seconds: 10);

  const OptimisticCount({this.confirmed = 0, List<DateTime> pending = const []})
      : _pending = pending;

  /// Сколько тапов ждут подтверждения.
  int get pending => _pending.length;

  /// Что показать человеку.
  int get display => confirmed + _pending.length;

  /// Тап: показываем +1, не дожидаясь сервера.
  OptimisticCount tap(DateTime now) =>
      OptimisticCount(confirmed: confirmed, pending: [..._pending, now]);

  /// Отправка не удалась — надбавку снимаем сразу, самую свежую.
  OptimisticCount failed() {
    if (_pending.isEmpty) return this;
    return OptimisticCount(
      confirmed: confirmed,
      pending: _pending.sublist(0, _pending.length - 1),
    );
  }

  /// Пришло значение с сервера. Рост снимает ровно столько ожиданий, на сколько
  /// сервер обогнал прежнее подтверждение; остальные ожидания доживают свой
  /// срок и уходят сами.
  OptimisticCount confirm(int serverCount, {required DateTime now}) {
    // Счётчик пары только растёт, поэтому значение меньше подтверждённого —
    // это устаревший снимок: офлайн-кэш отдал своё раньше сервера, подписка
    // переподнялась со старым числом, ответ пришёл не по порядку. Принимать
    // такое нельзя, иначе число прыгает назад у человека на глазах — жалоба
    // «Скучаю откатывается на предыдущие состояния» (13 августа 2026).
    // Настоящий сброс приходит не отсюда: другую пару начинает [reset].
    final accepted = serverCount > confirmed ? serverCount : confirmed;
    final grew = accepted - confirmed;
    var rest = _pending;
    if (grew > 0) {
      rest = rest.length <= grew ? const [] : rest.sublist(grew);
    }
    rest = rest.where((t) => now.difference(t) < ttl).toList();
    return OptimisticCount(confirmed: accepted, pending: rest);
  }

  /// Другая пара — всё старое здесь ни при чём.
  OptimisticCount reset() => const OptimisticCount();
}
