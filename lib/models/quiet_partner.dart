/// Партнёр давно не заходил.
///
/// Пары гаснут вдвоём: у 45% живых пар последние визиты расходятся меньше чем
/// на сутки, ещё у 30% — меньше чем на неделю. Момент, когда один затих, а
/// второй ещё открывает приложение, — последний, где можно что-то сделать.
/// Тогда и предлагаем отправить «Скучаю»: партнёр увидит это на своём экране.
///
/// Пуши здесь не при чём — FCM в проекте не используется, подсказка живёт
/// внутри приложения.
library;

abstract final class QuietPartner {
  /// Сколько тишины считается поводом. Двое суток: сутки — обычный ритм жизни,
  /// а на третий день человек уже замечает, что второго не слышно.
  static const Duration threshold = Duration(days: 2);

  /// Как часто можно предлагать. Раз в сутки, иначе подсказка превращается в
  /// требование.
  static const Duration cooldown = Duration(days: 1);

  /// Показывать ли карточку.
  ///
  /// [partnerSeenAtMs] — `user_presence.seen_at` партнёра, [lastNudgeAtMs] —
  /// когда мы в последний раз отправляли «Скучаю» с этой карточки.
  static bool shouldPrompt({
    required bool isPaired,
    required int? partnerSeenAtMs,
    required int nowMs,
    required int? lastNudgeAtMs,
  }) {
    if (!isPaired) return false;
    // Пустой seen_at бывает у тех, кто ни разу не открывал приложение после
    // подключения. Молчание тут не про «затих», а про «ещё не начинал».
    if (partnerSeenAtMs == null || partnerSeenAtMs <= 0) return false;
    if (nowMs - partnerSeenAtMs <= threshold.inMilliseconds) return false;
    if (lastNudgeAtMs != null &&
        nowMs - lastNudgeAtMs <= cooldown.inMilliseconds) {
      return false;
    }
    return true;
  }

  /// Сколько полных суток партнёр не заходил. null — отметки визита нет.
  static int? quietDays({required int? partnerSeenAtMs, required int nowMs}) {
    if (partnerSeenAtMs == null || partnerSeenAtMs <= 0) return null;
    final diff = nowMs - partnerSeenAtMs;
    if (diff <= 0) return 0;
    return diff ~/ Duration.millisecondsPerDay;
  }
}
