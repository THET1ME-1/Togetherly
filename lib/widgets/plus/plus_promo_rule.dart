import '../../services/plus_access.dart';

/// Как часто напоминаем про Togetherly+.
///
/// Семь часов — из просьбы заказчика («раз в 6–8 часов»). Реже незаметно, чаще
/// превращается в баннерную сеть внутри приложения.
const int kPlusPromoGapMs = 7 * 3600 * 1000;

/// Сколько молчим после установки. Витрина в первый день читается как «сначала
/// заплати», а человек ещё не успел понять, за что.
const int kPlusPromoQuietMs = 24 * 3600 * 1000;

/// Показывать ли плашку Togetherly+ прямо сейчас.
///
/// [gate] — `open` у купившего, `locked` у того, кому есть что предложить,
/// `hidden` на iPhone, где Плюса не существует вовсе.
bool shouldShowPlusPromo({
  required PlusGate gate,
  required int nowMs,
  required int lastShownMs,
  required int installedMs,
}) {
  if (gate != PlusGate.locked) return false;
  if (installedMs > 0 && nowMs - installedMs < kPlusPromoQuietMs) return false;
  if (lastShownMs <= 0) return true;
  // Часы устройства перевели назад: отметка из будущего означала бы «показывать
  // каждый раз».
  if (lastShownMs > nowMs) return false;
  return nowMs - lastShownMs >= kPlusPromoGapMs;
}
