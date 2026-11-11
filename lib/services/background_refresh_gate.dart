/// Нужно ли телефону просыпаться в фоне ради виджетов.
///
/// Фоновый проход обновляет только виджеты рабочего стола. Нет ни одного —
/// обновлять нечего, а каждый проход поднимает движок Flutter и ходит в сеть
/// (TOG-90). [widgetsOnScreen] — сколько наших виджетов стоит на столе,
/// `null` — система не ответила: тогда обновление остаётся, застывший виджет
/// хуже лишнего пробуждения.
bool backgroundRefreshWanted({required int? widgetsOnScreen}) =>
    widgetsOnScreen == null || widgetsOnScreen > 0;

/// Ключ отметки «виджеты обновлены» в хранилище виджетов, миллисекунды.
/// Пишет фоновый проход, читает запасная задача (`WidgetRefreshTick.kt`).
const String kWidgetsRefreshedAtKey = 'widgets_refreshed_at_ms';

/// Сколько обновление считается свежим, пока экран включён.
const Duration kWidgetFreshScreenOn = Duration(minutes: 14);

/// Сколько обновление считается свежим, пока экран выключен: виджет никто
/// не видит, а изменения партнёра приносит тихий пуш.
const Duration kWidgetFreshScreenOff = Duration(minutes: 60);

/// Пора ли запасной задаче будить Dart.
///
/// Задача приходит раз в 15 минут и дублирует тихий пуш. Движок Flutter она
/// поднимает, только когда прошлое обновление устарело. Само правило живёт в
/// Kotlin (`WidgetRefreshTick.due`): решать надо до подъёма Dart. Здесь его
/// копия под тестами, сторож сверяет сроки и отметку.
bool widgetTickDue({
  required int nowMs,
  required int refreshedAtMs,
  required bool screenOn,
}) {
  final age = nowMs - refreshedAtMs;
  // Когда обновляли, неизвестно или часы перевели назад — обновляем
  if (refreshedAtMs <= 0 || age < 0) return true;
  final fresh = screenOn ? kWidgetFreshScreenOn : kWidgetFreshScreenOff;
  return age >= fresh.inMilliseconds;
}
