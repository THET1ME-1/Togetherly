import '../../services/plus_access.dart';

/// Как часто напоминаем про Togetherly+.
///
/// Два с половиной дня — решение владельца 08.11.2026 («пусть раз в 2-3 дня
/// показывается»). Прежние семь часов при нескольких заходах в день читались
/// как «окно покупки при каждом заходе» (отзыв в App Store 29.09.2026).
const int kPlusPromoGapMs = 60 * 3600 * 1000;

/// Сколько молчим после установки. Витрина в первый день читается как «сначала
/// заплати», а человек ещё не успел понять, за что.
const int kPlusPromoQuietMs = 24 * 3600 * 1000;

/// Показывать ли плашку Togetherly+ прямо сейчас.
///
/// [gate] — `open` у купившего, `locked` у того, кому есть что предложить,
/// `hidden` на iPhone, где Плюса не существует вовсе.
///
/// [plusKnown] — читали ли уже флаг `users.plus` (с сервера или из локальной
/// копии). Пока не читали, `gate` врёт: холодный старт начинается с «не
/// куплено», и витрина успевала выскочить купившему до ответа сервера.
bool shouldShowPlusPromo({
  required PlusGate gate,
  required bool plusKnown,
  required int nowMs,
  required int lastShownMs,
  required int installedMs,
}) {
  if (!plusKnown) return false;
  if (gate != PlusGate.locked) return false;
  if (installedMs > 0 && nowMs - installedMs < kPlusPromoQuietMs) return false;
  if (lastShownMs <= 0) return true;
  // Часы устройства перевели назад: отметка из будущего означала бы «показывать
  // каждый раз».
  if (lastShownMs > nowMs) return false;
  return nowMs - lastShownMs >= kPlusPromoGapMs;
}
