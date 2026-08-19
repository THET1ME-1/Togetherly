import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/publish_gate.dart';

/// Публикация в канал разрешена ТОЛЬКО подписчику
/// (`allow_publish_for_subscriber` у namespace `watch`, `draw`, `pair`), и
/// Centrifugo проверяет это на своей стороне: клиент, который позвал
/// `subscribe()` и тут же `publish()`, получает `103 permission denied` —
/// подписка ещё в полёте.
///
/// В журнале сервера 19 августа 2026 это видно пачками: отклонённые штрихи
/// рисования и `voice-bye` в комнате просмотра. Человеку это выглядит как
/// «чат в совместном просмотре перестал работать» и «постоянно лагает»:
/// сообщение ушло, у себя видно, до партнёра не дошло.
void main() {
  group('awaitSubscribed', () {
    test('подписка уже есть — публикуем сразу, ничего не ждём', () async {
      var waited = false;
      final ok = await awaitSubscribed(
        isSubscribed: () => true,
        onSubscribed: () {
          waited = true;
          return Future<void>.value();
        },
      );
      expect(ok, isTrue);
      expect(waited, isFalse);
    });

    test('подписка в полёте — ждём её и публикуем', () async {
      final gate = Completer<void>();
      var subscribed = false;
      final future = awaitSubscribed(
        isSubscribed: () => subscribed,
        onSubscribed: () => gate.future,
      );
      await Future<void>.delayed(Duration.zero);
      subscribed = true;
      gate.complete();
      expect(await future, isTrue);
    });

    test('подписка не пришла за отведённое время — не публикуем', () async {
      final ok = await awaitSubscribed(
        isSubscribed: () => false,
        onSubscribed: () => Completer<void>().future,
        timeout: const Duration(milliseconds: 30),
      );
      expect(ok, isFalse);
    });

    test('обрыв подписки не роняет отправителя', () async {
      final ok = await awaitSubscribed(
        isSubscribed: () => false,
        onSubscribed: () => Future<void>.error(StateError('оборвалась')),
        timeout: const Duration(milliseconds: 30),
      );
      expect(ok, isFalse);
    });
  });
}
