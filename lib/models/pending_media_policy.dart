/// Отложенная заливка файла воспоминания: когда пробовать снова и когда сдаться.
///
/// Файл откладывается без сети и когда хранилище его не приняло
/// (`uploadWorthDeferring`). 9–10.11.2026 хранилище отказывало окнами по
/// несколько минут, и немедленные повторы укладывались в то же окно.
library;

/// Пауза перед следующей попыткой: 2, 4, 8, 16 минут, дальше по полчаса.
Duration pendingRetryDelay(int attempts) {
  const minutes = [2, 4, 8, 16];
  return Duration(
      minutes: attempts >= 0 && attempts < minutes.length
          ? minutes[attempts]
          : 30);
}

/// Бросить ли файл. Свежий не бросаем: это чьё-то фото, и хранилище может
/// лежать часами. [ageMs] — сколько файл ждёт; null у записи прежней сборки,
/// она живёт по прежнему правилу (восемь попыток).
bool pendingGiveUp({required int attempts, required int? ageMs}) {
  const maxAttempts = 8;
  const patienceMs = 3 * 24 * 60 * 60 * 1000;
  if (attempts < maxAttempts) return false;
  return ageMs == null || ageMs > patienceMs;
}
