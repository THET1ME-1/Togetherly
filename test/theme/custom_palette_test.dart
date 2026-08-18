// Своя тема Togetherly+: человек приносит цвет — из фотографии или пикером, —
// а приложение обязано развернуть его в такую же полноценную палитру, как
// готовые двадцать пять. Вся разница в том, что цель ([PaletteTarget]) тут не
// написана руками под предмет, а снята с принесённого цвета.
//
// Ловушки, ради которых эти проверки и написаны: у чёрного и белого предельная
// насыщенность равна нулю, и наивное деление на неё даёт NaN, а серый обязан
// остаться серым, иначе «свой цвет» подменяется голубым.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:love_app/models/custom_theme.dart';
import 'package:love_app/theme/app_palettes.dart';

double _hue(Color c) => Hct.fromInt(c.toARGB32()).hue;
double _chroma(Color c) => Hct.fromInt(c.toARGB32()).chroma;

void main() {
  group('customPalette — цвет человека становится палитрой', () {
    test('оттенок принесённого цвета доживает до заливки', () {
      for (final seed in const [
        Color(0xFFFF7E9B), // розовый
        Color(0xFF1685A2), // океан
        Color(0xFFF0A81C), // мёд
        Color(0xFF7C5CFF), // сиреневый
      ]) {
        final p = customPalette(seed, slot: 0);
        for (final brightness in Brightness.values) {
          final fill = paletteFill(p, brightness);
          expect(
            (_hue(fill) - _hue(seed)).abs(),
            lessThan(2.0),
            reason: 'цвет ${seed.toARGB32().toRadixString(16)}, '
                'режим ${brightness.name}',
          );
        }
      }
    });

    test('серый остаётся серым, а не превращается в голубой', () {
      final p = customPalette(const Color(0xFF808080), slot: 0);
      expect(_chroma(paletteFill(p, Brightness.light)), lessThan(4));
      expect(_chroma(paletteInk(p, Brightness.dark)), lessThan(4));
    });

    test('чёрный и белый не рождают NaN', () {
      for (final seed in const [Color(0xFF000000), Color(0xFFFFFFFF)]) {
        final p = customPalette(seed, slot: 0);
        expect(p.target.k.isFinite, isTrue,
            reason: 'k у ${seed.toARGB32().toRadixString(16)}');
        expect(p.target.k, inInclusiveRange(0.0, 1.0));
        for (final brightness in Brightness.values) {
          final fill = paletteFill(p, brightness);
          expect(fill.a, 1.0, reason: 'непрозрачная заливка');
        }
      }
    });

    test('насыщенность не выходит за край экрана', () {
      // k — доля от предельной насыщенности, достижимой в sRGB. Единица это
      // край; больше единицы M3 молча срежет, и цвет уедет от выбранного.
      for (final seed in const [
        Color(0xFF00FF00), // предельно кислотный зелёный
        Color(0xFFFF0000),
        Color(0xFF0000FF),
      ]) {
        expect(customPalette(seed, slot: 0).target.k, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('индексы своих тем', () {
    test('свой индекс не пересекается с готовыми палитрами', () {
      for (var slot = 0; slot < kMaxCustomThemes; slot++) {
        final index = customPaletteIndex(slot);
        expect(index, greaterThanOrEqualTo(kPalettes.length));
        expect(isCustomPaletteIndex(index), isTrue);
      }
    });

    test('индексы готовых палитр своими не считаются', () {
      for (final p in kPalettes) {
        expect(isCustomPaletteIndex(p.index), isFalse, reason: p.name);
      }
    });

    test('слот достаётся обратно из индекса', () {
      for (var slot = 0; slot < kMaxCustomThemes; slot++) {
        expect(customPaletteSlot(customPaletteIndex(slot)), slot);
      }
    });
  });

  group('цвет с краю всё равно даёт пригодную тему', () {
    test('чёрный и белый подтягиваются в рабочий диапазон светлоты', () {
      // Кнопки красятся тоном цели. Чистый чёрный делает их чёрными, а белый
      // растворяет в фоне светлой темы — обе крайности бесполезны как тема.
      for (final seed in const [Color(0xFF000000), Color(0xFF101010)]) {
        expect(customPalette(seed, slot: 0).target.tone,
            greaterThanOrEqualTo(20.0),
            reason: 'тёмный ${seed.toARGB32().toRadixString(16)}');
      }
      for (final seed in const [Color(0xFFFFFFFF), Color(0xFFF7F7F7)]) {
        expect(customPalette(seed, slot: 0).target.tone, lessThanOrEqualTo(88.0),
            reason: 'светлый ${seed.toARGB32().toRadixString(16)}');
      }
    });

    test('обесцвеченный цвет разворачивается нейтральной схемой', () {
      // Тот же приём, что у «Монохрома»: на сером сиде tonalSpot выдаёт
      // голубоватую схему, и «свой серый» перестаёт быть серым.
      final grey = customPalette(const Color(0xFF808080), slot: 0);
      expect(grey.variant, DynamicSchemeVariant.neutral);

      final pink = customPalette(const Color(0xFFFF7E9B), slot: 0);
      expect(pink.variant, DynamicSchemeVariant.tonalSpot);
    });
  });

  group('какая палитра активна', () {
    const mine = [
      CustomTheme(seed: Color(0xFF1685A2), name: 'Океан'),
      CustomTheme(seed: Color(0xFFF0A81C), name: 'Мёд'),
    ];

    test('готовая палитра берётся из списка', () {
      expect(paletteFor(7, mine).name, kPalettes[7].name);
    });

    test('свой индекс разворачивает свой цвет', () {
      expect(paletteFor(customPaletteIndex(1), mine).accent,
          const Color(0xFFF0A81C));
    });

    test('тема, удалённая на другом устройстве, откатывается к умолчанию', () {
      expect(paletteFor(customPaletteIndex(4), mine).name, kPalettes[0].name);
    });

    test('мусорный индекс не роняет тему', () {
      expect(paletteFor(-3, mine).name, kPalettes[0].name);
      expect(paletteFor(999, const []).name, kPalettes[0].name);
    });
  });
}
