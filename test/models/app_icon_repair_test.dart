import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/app_icon_repair.dart';

/// Две иконки на рабочем столе после обновления.
///
/// Жалоба со снимком 16.08.2026: «обновил, стало два» — рядом стоят прежняя
/// монограмма и новый маскот. Причина в том, как Android хранит состояние
/// `activity-alias`: выбранную иконку приложение включает явно
/// (`setComponentEnabledSetting`), и это переживает обновление, а новый
/// `.IconDefault` приезжает включённым из манифеста. Включённых становится
/// два — лаунчер честно рисует оба ярлыка.
///
/// Чинится не «включить дефолт всем»: человек выбирал иконку осознанно, и
/// отобрать её — вторая жалоба вместо первой.
void main() {
  group('нужен ли ремонт', () {
    test('один включённый — всё в порядке', () {
      expect(appIconNeedsRepair(const ['pink']), isFalse);
      expect(appIconNeedsRepair(const ['default']), isFalse);
    });

    test('два включённых — ровно тот случай со снимка', () {
      expect(appIconNeedsRepair(const ['default', 'pink']), isTrue);
    });

    test('ни одного включённого — тоже поломка: ярлык пропал совсем', () {
      expect(appIconNeedsRepair(const []), isTrue);
    });
  });

  group('какую иконку оставить', () {
    test('оставляем выбранную человеком, а не новую по умолчанию', () {
      expect(
        appIconToKeep(enabled: const ['default', 'pink'], saved: 'pink'),
        'pink',
      );
    });

    test('выбор не сохранён — оставляем ту, что человек включал явно', () {
      // В prefs пусто (выбор делался сборкой, которая их ещё не писала), но
      // среди включённых есть цветная: значит её и включали руками.
      expect(
        appIconToKeep(enabled: const ['default', 'purple'], saved: null),
        'purple',
      );
    });

    test('включённых нет вовсе — возвращаем основную', () {
      expect(appIconToKeep(enabled: const [], saved: null), 'default');
    });

    test('сохранённый выбор неизвестен приложению — не верим ему', () {
      expect(
        appIconToKeep(enabled: const ['default'], saved: 'сгинувшая'),
        'default',
      );
    });

    test('включена только основная — её и оставляем', () {
      expect(appIconToKeep(enabled: const ['default'], saved: null), 'default');
    });
  });
}
