import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Палитра обязана выглядеть так, как называется.
///
/// 8 августа 2026: схема M3 срезала у всех 25 палитр хрому до 36 и тон до 40,
/// оттого персиковая была коричневой, а розовая и вишнёвая — одним цветом.
/// Теперь у палитры есть цель: оттенок и тон от предмета, насыщенность —
/// доля от предельной. Заливка держит цвет, надпись держит контраст.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(int v) {
      final s = v / 255.0;
      return s <= 0.03928
          ? s / 12.92
          : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    final argb = c.toARGB32();
    return 0.2126 * ch((argb >> 16) & 0xFF) +
        0.7152 * ch((argb >> 8) & 0xFF) +
        0.0722 * ch(argb & 0xFF);
  }

  final l1 = lum(a), l2 = lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

Hct hct(Color c) => Hct.fromInt(c.toARGB32());

double hueGap(double a, double b) {
  final d = (a - b).abs();
  return math.min(d, 360 - d);
}

void main() {
  group('заливка совпадает с целью палитры', () {
    for (final p in kPalettes) {
      test('${p.name}: ${p.target.thing}', () {
        final t = buildAppTheme(p, Brightness.light);
        final f = hct(t.accentFill!);
        expect(hueGap(f.hue, p.target.hue), lessThan(4),
            reason: 'оттенок уехал от предмета');
        expect((f.tone - p.target.tone).abs(), lessThan(4),
            reason: 'светлота уехала от предмета');
      });
    }
  });

  test('персиковая — персик, а не коричневая', () {
    // Ровно та жалоба: оттенок 52 давал морковь, тон 40 давал грязь.
    // Эталоны, снятые с настоящих персиков: оттенок 25–36, тон 65–81.
    final f = hct(buildAppTheme(kPalettes[3], Brightness.light).accentFill!);
    expect(kPalettes[3].name, 'Персиковая');
    expect(f.hue, inInclusiveRange(24, 38));
    expect(f.tone, inInclusiveRange(68, 82));
    expect(f.chroma, greaterThan(35));
  });

  group('надпись на заливке читается', () {
    for (final p in kPalettes) {
      for (final b in Brightness.values) {
        test('${p.name} / ${b.name}', () {
          final t = buildAppTheme(p, b);
          expect(contrast(AppThemes.onColor(t.fillColor), t.fillColor),
              greaterThanOrEqualTo(4.5));
        });
      }
    }
  });

  group('надпись на фоне читается', () {
    for (final p in kPalettes) {
      for (final b in Brightness.values) {
        test('${p.name} / ${b.name}', () {
          final t = buildAppTheme(p, b);
          expect(contrast(t.primary, t.scheme!.surface),
              greaterThanOrEqualTo(4.5),
              reason: 'акцент текста не читается на фоне');
        });
      }
    }
  });

  test('палитры различимы между собой', () {
    final fills = [
      for (final p in kPalettes)
        (p.name, hct(buildAppTheme(p, Brightness.light).accentFill!)),
    ];
    final close = <String>[];
    for (var i = 0; i < fills.length; i++) {
      for (var j = i + 1; j < fills.length; j++) {
        final a = fills[i].$2, b = fills[j].$2;
        final d = math.sqrt(math.pow(hueGap(a.hue, b.hue) * 0.45, 2) +
            math.pow(a.chroma - b.chroma, 2) +
            math.pow(a.tone - b.tone, 2));
        // Лесная и Тёмный лес расходятся на 8: спорят сами названия, а не цвет.
        if (d < 7.5) close.add('${fills[i].$1} / ${fills[j].$1} — $d');
      }
    }
    expect(close, isEmpty);
  });

  test('насыщенность и светлота разведены, а не выровнены', () {
    final f = [
      for (final p in kPalettes)
        hct(buildAppTheme(p, Brightness.light).accentFill!),
    ];
    final chromas = f.map((h) => h.chroma).toList()..sort();
    final tones = f.map((h) => h.tone).toList()..sort();
    expect(chromas.last - chromas.first, greaterThan(60),
        reason: 'все палитры снова одной насыщенности');
    expect(tones.last - tones.first, greaterThan(35),
        reason: 'все палитры снова одной светлоты');
  });
}
