import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Вариант схемы, который человек выбрал, обязан доезжать до экранов на M3.
///
/// Жалоба 8 августа 2026: «в окне добавления вещи все цвета очень блёклые, хотя
/// тема не менялась». Тема вишнёвая, вариант «сочный»: главная красилась
/// `#BB005B`, а лист желания — `#8D4A5D`. Причина не в листе: `ProfileTheme`
/// строил схему заново из `AppTheme.primary`, а это уже ПРОИЗВОДНЫЙ тон, и
/// повторный сид скатывался в «мягкий» вариант. Так красились все 74 места, где
/// экран берёт тему через `ProfileTheme`.
void main() {
  final cherry = kPalettes.firstWhere((p) => p.name == 'Вишнёвая');

  group('ProfileTheme не теряет вариант схемы', () {
    for (final flavor in SchemeFlavor.values) {
      for (final brightness in Brightness.values) {
        test('${flavor.name} / ${brightness.name}: акцент тот же', () {
          final app = buildAppTheme(cherry, brightness, flavor: flavor);
          expect(ProfileTheme.themeFor(app).colorScheme.primary, app.primary);
        });
      }
    }

    test('вариант схемы правит поверхности, а не акцент', () {
      // С 8 августа 2026 акцент задаёт сама палитра (оттенок и тон от предмета),
      // поэтому «сочный» и «мягкий» дают ОДИН акцент — и это правильно:
      // персик обязан быть персиком при любом варианте. Вариант остаётся у
      // поверхностей, где он и работает: фон, карточки, разделители.
      final juicy = buildAppTheme(cherry, Brightness.light,
          flavor: SchemeFlavor.juicy);
      final soft =
          buildAppTheme(cherry, Brightness.light, flavor: SchemeFlavor.soft);

      expect(
        ProfileTheme.themeFor(juicy).colorScheme.primary,
        ProfileTheme.themeFor(soft).colorScheme.primary,
        reason: 'акцент обязан держаться палитры, а не варианта',
      );
      expect(
        ProfileTheme.themeFor(juicy).colorScheme.surfaceContainerHigh,
        isNot(ProfileTheme.themeFor(soft).colorScheme.surfaceContainerHigh),
        reason: 'поверхности вариант всё ещё различает',
      );
    });

    test('все палитры доносят свой акцент до листов', () {
      for (final p in kPalettes) {
        final app =
            buildAppTheme(p, Brightness.light, flavor: SchemeFlavor.juicy);
        expect(
          ProfileTheme.themeFor(app).colorScheme.primary,
          app.primary,
          reason: 'палитра «${p.name}»',
        );
      }
    });
  });

  _filledButtonUsesFill();

  test('тема без готовой схемы строится по-старому', () {
    // Статические `AppThemes.*` схемы не несут — им остаётся прежний путь через
    // сид, иначе витрина тем и тесты палитр останутся без цвета вовсе.
    final legacy = ProfileTheme.schemeFor(AppThemes.cherry);
    expect(legacy.brightness, Brightness.light);
    expect(legacy.primary, isNot(Colors.transparent));
  });
}

/// Залитая кнопка — это заливка, а не надпись.
///
/// «Сохранить» в листе желания брала `primary`, а с двумя акцентами это тёмный
/// тон под контраст: экран выглядел блёклым при сочной теме. Ровно та жалоба
/// от 8 августа 2026.
void _filledButtonUsesFill() {
  test('залитая кнопка красится заливкой темы', () {
    for (final p in kPalettes) {
      for (final b in Brightness.values) {
        final app = buildAppTheme(p, b);
        final style = ProfileTheme.themeFor(app).filledButtonTheme.style!;
        expect(style.backgroundColor?.resolve(const {}),
            app.scheme!.primaryContainer,
            reason: '${p.name} (${b.name}): кнопка взяла надписной акцент');
        expect(style.foregroundColor?.resolve(const {}),
            app.scheme!.onPrimaryContainer);
      }
    }
  });
}
