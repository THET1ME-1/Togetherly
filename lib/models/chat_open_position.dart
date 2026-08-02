/// Куда встать при открытии чата.
enum ChatOpenPosition {
  /// К последнему сообщению — обычный случай.
  bottom,

  /// К маркеру «Новые сообщения»: есть непрочитанные.
  unreadMarker,

  /// Туда, где человек вышел прошлый раз.
  savedOffset,
}

/// Решает, куда прокрутить чат при открытии.
///
/// Раньше чат всегда возвращался на сохранённую позицию в ПИКСЕЛЯХ, и это
/// подводило: за время отсутствия приходили новые сообщения, окно ленты снова
/// начиналось с последних тридцати, а картинки догружались уже после первой
/// раскладки — те же пиксели указывали в другое место. Человек открывал чат и
/// оказывался где-то посреди старой переписки («пролистывается куда-то вверх,
/// приходится листать вниз», жалоба от 31 июля).
///
/// Правило теперь такое, как в мессенджерах:
///   * есть непрочитанные — встаём на их маркер;
///   * человек читал с самого низа — открываем внизу;
///   * человек ушёл, отлистав вверх, и с тех пор ничего не пришло — возвращаем
///     туда же: он явно читал старое и хочет продолжить.
///
/// [savedOffset] — сохранённые пиксели (null, если не сохраняли),
/// [savedWasNearBottom] — стоял ли он у низа в момент выхода,
/// [hasUnread] — есть ли маркер непрочитанных,
/// [newMessagesSinceExit] — приходили ли сообщения после выхода.
ChatOpenPosition chatOpenPosition({
  required double? savedOffset,
  required bool savedWasNearBottom,
  required bool hasUnread,
  required bool newMessagesSinceExit,
}) {
  if (hasUnread) return ChatOpenPosition.unreadMarker;
  if (savedOffset == null || savedOffset <= 0) return ChatOpenPosition.bottom;
  if (savedWasNearBottom) return ChatOpenPosition.bottom;
  // Лента переехала — старые пиксели указывают мимо, низ честнее.
  if (newMessagesSinceExit) return ChatOpenPosition.bottom;
  return ChatOpenPosition.savedOffset;
}
