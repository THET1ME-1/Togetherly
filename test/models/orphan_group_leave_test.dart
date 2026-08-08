import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/connection.dart';

/// Пару с пустым местом нельзя принимать за осиротевшую группу.
///
/// 8 августа 2026: живой снимок группы уходил в ветку «партнёров не осталось» и
/// вызывал `leaveGroup` — через полсекунды после создания. На проде так умерли
/// ВСЕ 52 пары с пустым местом: `members` пуст, `disbanded = 1`, `updated`
/// отстаёт от `created_at` на 0,5–1,7 секунды. Ни одна пара не прожила и двух
/// секунд, ни в одной не появилось ни сообщения, ни воспоминания.
void main() {
  group('shouldLeaveOrphanGroup', () {
    test('обычная пара без партнёров — осиротевшая, выходим', () {
      expect(
        shouldLeaveOrphanGroup(
          isPaired: true,
          partnersCount: 0,
          waitingMode: false,
        ),
        isTrue,
      );
    });

    test('пара с пустым местом партнёра не ждёт — не трогаем', () {
      expect(
        shouldLeaveOrphanGroup(
          isPaired: true,
          partnersCount: 0,
          waitingMode: true,
        ),
        isFalse,
      );
    });

    test('партнёр на месте — выходить не из чего', () {
      expect(
        shouldLeaveOrphanGroup(
          isPaired: true,
          partnersCount: 1,
          waitingMode: false,
        ),
        isFalse,
      );
    });

    test('не спаренная связь сервер не трогает', () {
      expect(
        shouldLeaveOrphanGroup(
          isPaired: false,
          partnersCount: 0,
          waitingMode: false,
        ),
        isFalse,
      );
    });
  });
}
