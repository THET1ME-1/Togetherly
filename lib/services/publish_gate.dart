/// Ждать ли подписку перед публикацией — и сколько.
///
/// Namespace `watch`, `draw` и `pair` разрешают публиковать только тем, кто на
/// канал подписан. Подписка устанавливается раундтрипом с токеном, поэтому
/// `subscribe()` и сразу `publish()` — это `103 permission denied` на сервере и
/// потерянное сообщение у человека.
library;

import 'dart:async';

/// Сколько ждём подписку, прежде чем бросить попытку.
///
/// Две секунды: столько занимает раундтрип даже на плохой связи, а дольше
/// держать штрих или реплику незачем — данные эфемерные, и «не отправилось»
/// честнее, чем отправка в никуда через полминуты.
const Duration kPublishWait = Duration(seconds: 2);

/// Готов ли канал принять публикацию.
///
/// [isSubscribed] — состояние прямо сейчас, [onSubscribed] — ожидание события
/// «подписались». Возвращает false, если ждать не дождались: публиковать в
/// этом состоянии бессмысленно, сервер всё равно откажет.
Future<bool> awaitSubscribed({
  required bool Function() isSubscribed,
  required Future<void> Function() onSubscribed,
  Duration timeout = kPublishWait,
}) async {
  if (isSubscribed()) return true;
  try {
    await onSubscribed().timeout(timeout);
  } catch (_) {
    // Таймаут, обрыв, отказ сервера — для отправителя это одно и то же:
    // публиковать нельзя.
    return isSubscribed();
  }
  return isSubscribed();
}
