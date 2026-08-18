// Свои темы лежат в `users.custom_themes` — json-поле, а такие поля приезжают
// с сервера строкой, списком или вовсе пустотой, и ключи в них бывают чужие.
// Кривая запись не имеет права ронять настройки: там же живёт выбор палитры,
// режим и всё оформление разом.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/custom_theme.dart';
import 'package:love_app/theme/app_palettes.dart';

void main() {
  group('разбор поля', () {
    test('список приходит строкой с json внутри', () {
      final list = parseCustomThemes(
          '[{"seed":4294934171,"name":"Наш"},{"seed":4283519138}]');
      expect(list, hasLength(2));
      expect(list.first.seed, const Color(0xFFFF7E9B));
      expect(list.first.name, 'Наш');
      expect(list.last.name, isEmpty);
    });

    test('список приходит уже разобранным', () {
      final list = parseCustomThemes([
        {'seed': 4294934171, 'name': 'Наш'}
      ]);
      expect(list, hasLength(1));
      expect(list.first.seed, const Color(0xFFFF7E9B));
    });

    test('пустота и мусор дают пустой список, а не падение', () {
      for (final raw in [null, '', '[]', 'не json', 42, {'seed': 1}]) {
        expect(parseCustomThemes(raw), isEmpty, reason: '$raw');
      }
    });

    test('запись без цвета пропускается, соседи остаются', () {
      final list = parseCustomThemes(
          '[{"name":"без цвета"},{"seed":4283519138,"name":"Океан"}]');
      expect(list, hasLength(1));
      expect(list.single.name, 'Океан');
    });

    test('цвет пережил запись и чтение', () {
      const theme = CustomTheme(seed: Color(0xFF1685A2), name: 'Океан');
      final back = parseCustomThemes(encodeCustomThemes([theme]));
      expect(back.single.seed, theme.seed);
      expect(back.single.name, theme.name);
    });

    test('лишние записи сверх пяти отбрасываются при чтении', () {
      final raw = List.generate(8, (i) => '{"seed":${4294934171 + i}}').join(',');
      expect(parseCustomThemes('[$raw]'), hasLength(kMaxCustomThemes));
    });
  });

  group('правка набора', () {
    const a = CustomTheme(seed: Color(0xFFFF7E9B), name: 'A');
    const b = CustomTheme(seed: Color(0xFF1685A2), name: 'B');

    test('шестая тема не влезает', () {
      final full = List.generate(
          kMaxCustomThemes, (i) => CustomTheme(seed: Color(0xFF000010 + i)));
      expect(addCustomTheme(full, a), hasLength(kMaxCustomThemes));
      expect(addCustomTheme(full, a).contains(a), isFalse);
    });

    test('новая тема встаёт в конец', () {
      expect(addCustomTheme(const [a], b), [a, b]);
    });

    test('правка меняет тему на месте', () {
      expect(replaceCustomTheme(const [a, b], 1, a), [a, a]);
    });

    test('правка мимо набора ничего не портит', () {
      expect(replaceCustomTheme(const [a], 3, b), [a]);
      expect(removeCustomTheme(const [a], 3), [a]);
    });
  });

  group('выбор темы после правки набора', () {
    test('удаление темы левее выбранной сдвигает выбор за ней', () {
      // Выбран второй свой цвет (индекс 1001), удалили первый — тот же цвет
      // теперь лежит в нулевом слоте, и выбор обязан уехать вместе с ним.
      expect(themeIdAfterRemoval(customPaletteIndex(1), 0),
          customPaletteIndex(0));
    });

    test('удаление темы правее выбранной оставляет выбор на месте', () {
      expect(themeIdAfterRemoval(customPaletteIndex(1), 2),
          customPaletteIndex(1));
    });

    test('удаление выбранной темы возвращает на палитру по умолчанию', () {
      expect(themeIdAfterRemoval(customPaletteIndex(1), 1), 0);
    });

    test('готовая палитра удалением своей темы не задета', () {
      expect(themeIdAfterRemoval(7, 0), 7);
    });
  });

  group('порядок кружков в ленте оформления', () {
    test('первым идёт «завести свою», за ней свои темы, потом готовые', () {
      final strip = paletteStripEntries(customCount: 2, plusVisible: true);
      expect(strip[0], const StripEntry.add());
      expect(strip[1], const StripEntry.custom(0));
      expect(strip[2], const StripEntry.custom(1));
      expect(strip[3], const StripEntry.palette(0));
    });

    test('на iPhone у некупившего своих кружков нет вовсе', () {
      final strip = paletteStripEntries(customCount: 0, plusVisible: false);
      expect(strip.first, const StripEntry.palette(0));
      expect(strip.every((e) => e.isPalette), isTrue);
    });

    test('готовые палитры не теряются и не задваиваются', () {
      final strip = paletteStripEntries(customCount: 3, plusVisible: true);
      final palettes = strip.where((e) => e.isPalette).map((e) => e.index);
      expect(palettes, List.generate(kPalettes.length, (i) => i));
    });
  });
}
