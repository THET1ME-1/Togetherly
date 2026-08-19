import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/session_restore.dart';

/// Полумёртвая сессия: токен живой, а запись профиля пустая. Приложение в этом
/// состоянии работает, но своего имени и аватара не знает — человек видит букву
/// вместо фотографии и «вместе 2 дня» вместо настоящего срока (жалоба
/// тестировщицы 19 августа 2026, лечилась выходом и повторным входом).
void main() {
  group('needsProfileRestore', () {
    test('токен есть, записи нет — чиним', () {
      expect(
        needsProfileRestore(hasSession: true, recordId: ''),
        isTrue,
      );
      expect(
        needsProfileRestore(hasSession: true, recordId: null),
        isTrue,
      );
    });

    test('запись на месте — не трогаем', () {
      expect(
        needsProfileRestore(hasSession: true, recordId: 'lwtvwi43fd0ld8m'),
        isFalse,
      );
    });

    test('без сессии чинить нечего', () {
      // Человек не вошёл: пустой профиль тут — норма, а не поломка.
      expect(needsProfileRestore(hasSession: false, recordId: ''), isFalse);
    });
  });

  group('mayRetryProfileRestore', () {
    const now = 1786000000000;

    test('первая попытка идёт сразу', () {
      expect(mayRetryProfileRestore(nowMs: now, lastTryMs: 0), isTrue);
    });

    test('подряд не долбим', () {
      // Сервер мог не ответить по своей беде; повтор каждую секунду с каждого
      // телефона — это и есть тот наплыв, от которого уже страдал сервер.
      expect(
        mayRetryProfileRestore(nowMs: now, lastTryMs: now - 3000),
        isFalse,
      );
    });

    test('через паузу пробуем снова', () {
      expect(
        mayRetryProfileRestore(
          nowMs: now,
          lastTryMs: now - kProfileRestoreGapMs,
        ),
        isTrue,
      );
    });

    test('часы перевели назад — не считаем это разрешением', () {
      expect(
        mayRetryProfileRestore(nowMs: now, lastTryMs: now + 60000),
        isFalse,
      );
    });
  });
}
