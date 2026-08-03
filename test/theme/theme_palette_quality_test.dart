import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Качество палитр: заказчик сказал «нормальные только первые две», и это
/// видно числом. Вариант `vibrant` задирал насыщенность у зелёных, жёлтых и
/// бирюзовых сидов до 0.85–0.93, тогда как у розовой и фиолетовой она 0.26–0.30.
/// Кислотная кнопка на тёмном фоне и есть та разница, которую человек назвал
/// «некачественные темы».
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
  group('палитры', () {
    test('ни одна тема не кислотная', () {
      // Порог взят по эталону: у розовой и фиолетовой 0.26–0.30, у тёплых
      // жёлтых оттенков насыщенность естественно выше, но не вдвое.
      for (final palette in kPalettes) {
        for (final brightness in Brightness.values) {
          final scheme = ProfileTheme.schemeOf(palette.accent, brightness);
          expect(
            _chroma(scheme.primary),
            lessThan(0.62),
            reason: '${palette.name} (${brightness.name}) слишком насыщенная',
          );
        }
      }
    });

    test('текст читается на всех поверхностях', () {
      for (final palette in kPalettes) {
        for (final brightness in Brightness.values) {
          final s = ProfileTheme.schemeOf(palette.accent, brightness);
          final pairs = {
            'primary': (s.onPrimary, s.primary),
            'primaryContainer': (s.onPrimaryContainer, s.primaryContainer),
            'secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
            'surface': (s.onSurface, s.surface),
            'surfaceVariant': (s.onSurfaceVariant, s.surfaceContainerHighest),
          };
          for (final e in pairs.entries) {
            expect(
              _contrast(e.value.$1, e.value.$2),
              greaterThanOrEqualTo(4.5),
              reason: '${palette.name} (${brightness.name}), ${e.key}',
            );
          }
        }
      }
    });

    test('акцент отличим от поверхности', () {
      // Кнопка не должна сливаться с карточкой, на которой лежит.
      for (final palette in kPalettes) {
        for (final brightness in Brightness.values) {
          final s = ProfileTheme.schemeOf(palette.accent, brightness);
          expect(
            _contrast(s.primary, s.surfaceContainerHigh),
            greaterThan(1.5),
            reason: '${palette.name} (${brightness.name})',
          );
        }
      }
    });
  });
}
