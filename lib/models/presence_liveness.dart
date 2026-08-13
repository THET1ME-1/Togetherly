/// Кто сейчас «в сети» — правило без сети и без таймеров.
///
/// Раньше присутствие держалось на записи в базу: каждый телефон обновлял
/// `user_presence.seen_at` раз в двенадцать секунд. При семистах активных это
/// под шестьдесят записей в секунду на единственного писателя SQLite — то есть
/// почти весь поток записи уходил на «я ещё тут». Ночью 14 августа 2026 сервер
/// на этом и захлебнулся: сохранение статуса вставало в очередь за
/// heartbeat'ами и висело по тридцать секунд.
///
/// Теперь «я жив» летит в канал пары через Centrifugo и на диск не попадает
/// вовсе, а в базу пишется редкая отметка — только чтобы шапка чата могла
/// сказать «была в 12:33».
///
/// Оба источника учитываются вместе: партнёр может сидеть на сборке постарше и
/// про канал ещё не знать. Пока такие сборки живы, его онлайн виден по базе.
library;

class PresenceLiveness {
  /// Сколько времени отметка считается свежей.
  ///
  /// Канал бьёт раз в 20 секунд, поэтому 45 переживают один пропущенный удар
  /// и не гасят точку на ровном месте.
  static const Duration freshness = Duration(seconds: 45);

  /// Как часто отправлять «я жив» в канал пары.
  static const Duration beat = Duration(seconds: 20);

  /// Как часто класть отметку «был в сети» в базу.
  ///
  /// В двадцать пять раз реже прежнего heartbeat: этого хватает подписи «была
  /// в 12:33», а писателя базы почти не трогает.
  static const Duration lastSeenWrite = Duration(minutes: 5);

  /// В сети ли человек, если последний признак жизни пришёл в [lastSignalMs].
  ///
  /// Сигналом считается и удар по каналу, и отметка в базе — берём тот, что
  /// свежее. Обе величины в миллисекундах эпохи; null означает «признака нет».
  static bool isOnline({
    int? channelBeatMs,
    int? storedSeenMs,
    required int nowMs,
  }) {
    final latest = _latest(channelBeatMs, storedSeenMs);
    if (latest == null) return false;
    final age = nowMs - latest;
    return age >= 0 && age < freshness.inMilliseconds;
  }

  /// Когда человека видели в последний раз: для подписи «была в 12:33».
  static int? lastSeenMs({int? channelBeatMs, int? storedSeenMs}) =>
      _latest(channelBeatMs, storedSeenMs);

  /// Пора ли класть отметку в базу.
  static bool shouldWriteLastSeen({int? writtenAtMs, required int nowMs}) {
    if (writtenAtMs == null) return true;
    return nowMs - writtenAtMs >= lastSeenWrite.inMilliseconds;
  }

  static int? _latest(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }
}
