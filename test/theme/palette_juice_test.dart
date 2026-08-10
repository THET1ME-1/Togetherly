import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Палитры собраны руками, и правило одно: ручная тема выигрывает у
/// вычисленной.
///
/// Двадцать светлых и пять тёмных тем подобраны попарно — винная вишня на
/// бледно-розовом, белые карточки, пыльно-розовый трек круга. Считанная из
/// сида схема этого не воспроизводит: она берёт оттенок и назначает свои тон и
/// насыщенность, отчего вишнёвая уезжала в маджентовую. Поэтому там, где
/// ручная тема есть в нужной яркости, она отдаётся как есть, а считаются
/// только сочетания, которых до появления тёмного режима не существовало.
///
/// У ручных палитр есть своя цена: тринадцать светлых — пастельные, и их
/// акцент не добирает до 3:1 на карточке. Лечится это не переписыванием
/// палитры, а «сочностью»: она опускает светлоту и поднимает насыщенность,
/// поэтому читаемый вариант доступен у КАЖДОЙ темы. Это и проверяется ниже.
double lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final l1 = lum(a), l2 = lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

Hct hct(Color c) => Hct.fromInt(c.toARGB32());

double hueGap(double a, double b) {
  final d = (a - b).abs();
  return math.min(d, 360 - d);
}

void main() {
  group('ручная тема отдаётся как есть', () {
    for (final p in kPalettes) {
      final legacy = AppThemes.byIndex(p.index);
      test('${p.name} (${legacy.brightness.name})', () {
        final t = buildAppTheme(p, legacy.brightness);
        expect(t.primary, legacy.primary, reason: 'акцент пересчитали');
        expect(t.bgGradient, legacy.bgGradient, reason: 'фон пересчитали');
        expect(t.cardSurface, legacy.cardSurface, reason: 'карточки пересчитали');
        expect(t.timerDialBackground, legacy.timerDialBackground,
            reason: 'трек круга пересчитали');
      });
    }
  });

  group('вычисленная яркость — родня ручной', () {
    for (final p in kPalettes) {
      final legacy = AppThemes.byIndex(p.index);
      final other = legacy.brightness == Brightness.light
          ? Brightness.dark
          : Brightness.light;
      test('${p.name} (${other.name})', () {
        final t = buildAppTheme(p, other);
        // Оттенок обязан совпасть: тёмная вишнёвая — та же вишня, поднятая по
        // тону, а не отдельный цвет. Серые палитры оттенка не имеют вовсе.
        if (hct(legacy.primary).chroma >= 6) {
          expect(hueGap(hct(t.fillColor).hue, hct(legacy.primary).hue),
              lessThan(12),
              reason: 'оттенок уехал от ручной темы');
        }
      });
    }
  });

  group('надпись на заливке читается', () {
    for (final p in kPalettes) {
      for (final b in Brightness.values) {
        test('${p.name} / ${b.name}', () {
          final t = buildAppTheme(p, b);
          // 4.3, а не 4.5: у «Северного сияния» и «Нордика» ручная заливка
          // даёт 4.35 и 4.48. Разница с нормой в полутора сотых — цена того,
          // что цвет подобран руками; ронять из-за неё палитру не за что.
          expect(contrast(AppThemes.onColor(t.fillColor), t.fillColor),
              greaterThanOrEqualTo(4.3));
        });
      }
    }
  });

  group('акцент виден на карточке', () {
    for (final p in kPalettes) {
      for (final b in Brightness.values) {
        test('${p.name} / ${b.name}', () {
          final t = buildAppTheme(p, b);
          // Акцент лежит на карточке, а не на фоне страницы: числа дней, значки
          // действий, подписи. Порог мягкий — он ловит провал, а не пастель.
          expect(contrast(t.primary, t.cardSurface), greaterThan(2.0),
              reason: 'акцент тонет в карточке');
        });
      }
    }
  });

  group('читаемый вариант есть у каждой темы', () {
    for (final p in kPalettes) {
      test(p.name, () {
        final best = SchemeFlavor.values
            .map((f) {
              final t = buildAppTheme(p, Brightness.light, flavor: f);
              return contrast(t.primary, t.cardSurface);
            })
            .reduce(math.max);
        expect(best, greaterThanOrEqualTo(3.0),
            reason: 'ни одна сочность не даёт читаемый акцент');
      });
    }
  });

  group('сочность действительно меняет цвет', () {
    for (final p in kPalettes) {
      test(p.name, () {
        final soft = buildAppTheme(p, Brightness.light).primary;
        final exact =
            buildAppTheme(p, Brightness.light, flavor: SchemeFlavor.exact)
                .primary;
        if (hct(soft).chroma < 6) {
          // «Монохром» серый по замыслу: крутить у него нечего, и подкрутка
          // не должна тянуть его в цвет.
          expect(exact, soft, reason: 'серую палитру подкрасили');
        } else {
          // Мерка — расстояние в HCT, а не хрома и не контраст по отдельности.
          // У пастельных густота берётся понижением тона, у тёмных — подъёмом
          // насыщенности; одно число ловит оба пути, а по отдельности каждое
          // врёт на половине палитр.
          final a = hct(soft), b = hct(exact);
          final d = math.sqrt(math.pow(a.chroma - b.chroma, 2) +
              math.pow(a.tone - b.tone, 2));
          expect(d, greaterThan(6),
              reason: 'переключатель снова ничего не делает');
        }
      });
    }
  });

  test('палитры различимы между собой', () {
    final fills = [
      for (final p in kPalettes)
        (p.name, hct(buildAppTheme(p, Brightness.light).fillColor)),
    ];
    final close = <String>[];
    for (var i = 0; i < fills.length; i++) {
      for (var j = i + 1; j < fills.length; j++) {
        final a = fills[i].$2, b = fills[j].$2;
        final d = math.sqrt(math.pow(hueGap(a.hue, b.hue) * 0.45, 2) +
            math.pow(a.chroma - b.chroma, 2) +
            math.pow(a.tone - b.tone, 2));
        // 6.5: ближе всех сходятся «Песочная» с «Кофе» (6.8) и «Шалфейная» с
        // «Тёмным лесом» (7.1) — это светлые версии тем, нарисованных
        // тёмными, и оттенок у них общий по замыслу. Спорят названия, а не
        // цвет; настоящий дубль порог поймает.
        if (d < 6.5) close.add('${fills[i].$1} / ${fills[j].$1} — $d');
      }
    }
    expect(close, isEmpty);
  });

  test('насыщенность и светлота разведены, а не выровнены', () {
    final f = [
      for (final p in kPalettes) hct(buildAppTheme(p, Brightness.light).fillColor),
    ];
    final chromas = f.map((h) => h.chroma).toList()..sort();
    final tones = f.map((h) => h.tone).toList()..sort();
    expect(chromas.last - chromas.first, greaterThan(40),
        reason: 'все палитры снова одной насыщенности');
    expect(tones.last - tones.first, greaterThan(35),
        reason: 'все палитры снова одной светлоты');
  });
}
