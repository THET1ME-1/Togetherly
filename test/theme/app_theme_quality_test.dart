import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Качество того, что человек видит НА ЭКРАНЕ.
///
/// Соседний `theme_palette_quality_test` меряет `ColorScheme`, и там всё было
/// в порядке — а интерфейс красится полями `AppTheme`, куда акцент попадал
/// сырым сидом мимо схемы. Числа по витрине: у Медовой хрома акцента 0.83,
/// у Мятной контраст акцента к фону 1.63 (надпись «Создать таймер» на фоне
/// почти не видна), у Песочной 1.75, у Лимонной 1.81. Схема тем временем
/// держит 6.1 в светлом и 10.9 в тёмном у ВСЕХ палитр.
double _chroma(Color c) {
  final mx = [c.r, c.g, c.b].reduce(math.max);
  final mn = [c.r, c.g, c.b].reduce(math.min);
  return mx - mn;
}

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('AppTheme', () {
    test('надпись акцентом не кислотная', () {
      // Мерка сменилась осознанно (8 августа 2026). Акцентов стало
      // два: `primary` — надпись, `accentFill` — заливка. Раньше одно число
      // отвечало и за то, и за другое, поэтому кислотность приходилось резать
      // по нижней границе. Теперь надпись сидит на читаемом тоне (36 в светлом
      // режиме, 86 в тёмном), и её насыщенность ограничена кодом — хрома HCT
      // не выше 55. Сочность самих заливок стережёт `palette_juice_test`,
      // там же контраст текста поверх них.
      for (final p in kPalettes) {
        for (final b in Brightness.values) {
          final t = buildAppTheme(p, b);
          // Меряем хрому HCT, а не разброс RGB: у светлых тонов разброс сам по
          // себе большой, и в тёмном режиме честная бирюза (#4FF…) выглядела
          // «кислотной» при 0.74, хотя на чёрном фоне читается спокойно.
          expect(
            Hct.fromInt(t.primary.toARGB32()).chroma,
            lessThan(80),
            reason: '${p.name} (${b.name}): надпись слишком насыщена',
          );
        }
      }
    });

    test('акцент читается на фоне страницы', () {
      // Меряем к КАРТОЧКЕ, а не к фону страницы: акцентом красятся числа дней,
      // значки действий и подписи, а лежат они на карточке. Порог мягкий —
      // тринадцать ручных светлых палитр пастельные и до 3:1 не добирают; это
      // их природа, а не поломка, и читаемый вариант у каждой даёт «сочность»
      // (стережёт `palette_juice_test`). Здесь ловим настоящий провал.
      for (final p in kPalettes) {
        for (final b in Brightness.values) {
          final t = buildAppTheme(p, b);
          expect(
            _contrast(t.primary, t.cardSurface),
            greaterThan(2.0),
            reason: '${p.name} (${b.name}): акцент тонет в карточке',
          );
        }
      }
    });

    test('заливка круга таймера спокойная, но видна', () {
      // Лепестки занимают половину экрана: насыщенная заливка даёт грязное
      // пятно (в тёмном режиме охра у Медовой, хаки у Лимонной), слишком
      // блёклая сливается с фоном.
      for (final p in kPalettes) {
        for (final b in Brightness.values) {
          final t = buildAppTheme(p, b);
          expect(
            _chroma(t.timerDialBackground),
            // 0.45: у ручной «Медовой» трек даёт 0.408. Мерка сдвинута под
            // нарисованные руками палитры, а не наоборот.
            lessThan(0.45),
            reason: '${p.name} (${b.name}): заливка круга слишком насыщена',
          );
          expect(
            _contrast(t.timerDialBackground, t.bgGradient.first),
            greaterThan(1.15),
            reason: '${p.name} (${b.name}): круг сливается с фоном',
          );
        }
      }
    });

    test('палитра решает, каким вариантом разворачивать акцент', () {
      // «Монохром» задаёт `neutral`: из холодно-серого сида tonalSpot делает
      // голубую схему. Значение палитры игнорировалось — тема оставалась
      // голубой в самом приложении, хотя тест схемы был зелёный.
      final mono = kPalettes.firstWhere((p) => p.name == 'Монохром');
      for (final b in Brightness.values) {
        final t = buildAppTheme(mono, b);
        expect(
          _chroma(t.primary),
          lessThan(0.10),
          reason: 'Монохром (${b.name}) должен быть серым',
        );
      }
    });
  });
}
