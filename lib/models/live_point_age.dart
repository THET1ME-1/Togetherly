import 'package:flutter/foundation.dart';

/// Насколько давно снята точка партнёра на карте «Где мы».
///
/// Точка не удаляется, когда человек закрывает приложение: на карте всегда
/// висит последняя известная. Пока карта об этом молчала, метка двухдневной
/// давности выглядела точно так же, как живая, — отсюда жалоба «партнёр не
/// заходил два дня, метка не сдвинулась». Отличить «он дома» от «данных нет»
/// было нечем: на карточке главной давность не показывалась вовсе, на экране
/// карты метка просто бледнела.
///
/// Порог намеренно крупный. Точка уходит в канал при смещении на 15 метров, и
/// человек, который сидит дома или спит, честно не шлёт ничего часами — подпись
/// «обновлено 3 минуты назад» пугала бы там, где всё работает.
enum LivePointAgeUnit {
  /// Свежая или почти свежая: подписывать нечем.
  fresh,

  /// Времени у точки нет — так лежат записи, сделанные до появления поля.
  unknown,

  minutes,
  hours,
  days,
}

@immutable
class LivePointAge {
  final LivePointAgeUnit unit;

  /// Сколько минут, часов или дней прошло. У `fresh` и `unknown` — ноль.
  final int value;

  const LivePointAge(this.unit, this.value);

  /// Подпись нужна только тому, у кого точка успела состариться.
  bool get needsCaption =>
      unit == LivePointAgeUnit.minutes ||
      unit == LivePointAgeUnit.hours ||
      unit == LivePointAgeUnit.days;

  /// До этого срока молчим: человек мог просто не двигаться.
  static const Duration fresh = Duration(minutes: 15);

  /// [updatedAtMs] — время точки (epoch ms, ставит телефон автора).
  static LivePointAge of(int updatedAtMs, {required int nowMs}) {
    if (updatedAtMs <= 0) return const LivePointAge(LivePointAgeUnit.unknown, 0);
    final diff = nowMs - updatedAtMs;
    // Часы на телефоне партнёра бывают убежавшими вперёд — на проде есть точки
    // с датой из будущего. Такую считаем свежей, а не «минус два дня назад».
    if (diff < fresh.inMilliseconds) {
      return const LivePointAge(LivePointAgeUnit.fresh, 0);
    }
    final minutes = diff ~/ 60000;
    if (minutes < 60) return LivePointAge(LivePointAgeUnit.minutes, minutes);
    final hours = minutes ~/ 60;
    if (hours < 24) return LivePointAge(LivePointAgeUnit.hours, hours);
    return LivePointAge(LivePointAgeUnit.days, hours ~/ 24);
  }
}
