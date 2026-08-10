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

    test('сочность правит акцент и доезжает до листов', () {
      // Мерка перевернулась осознанно. Раньше «сочность» меняла ВАРИАНТ схемы,
      // то есть нейтральные поверхности на волосок, а акцент считался мимо неё
      // — переключатель стоял и не делал ничего, о чём и была жалоба. Теперь
      // он крутит саму насыщенность акцента, и изменённый цвет обязан доехать
      // до экранов на M3 ровно так же, как доезжает исходный.
      final juicy = buildAppTheme(cherry, Brightness.light,
          flavor: SchemeFlavor.juicy);
      final soft =
          buildAppTheme(cherry, Brightness.light, flavor: SchemeFlavor.soft);

      expect(juicy.primary, isNot(soft.primary),
          reason: 'сочность снова ничего не меняет');
      expect(ProfileTheme.themeFor(juicy).colorScheme.primary, juicy.primary);
      expect(ProfileTheme.themeFor(soft).colorScheme.primary, soft.primary);

      // Фон и карточки при этом остаются прежними: «сочность» про цвет темы,
      // а не про то, чтобы залить страницу.
      expect(juicy.bgGradient, soft.bgGradient);
      expect(juicy.cardSurface, soft.cardSurface);
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
  test('залитая кнопка красится цветом темы, а не подложкой', () {
    // Пара вернулась к стандартной M3: заливка `primary`, надпись `onPrimary`.
    // Обход через контейнер завели, когда `primary` был тёмным тоном под
    // контраст. У нарисованных руками палитр `primary` — сам цвет темы, а
    // контейнер снова светлая подложка: пока он совпадал с акцентом, значок
    // цветом `primary` на подложке `primaryContainer` был не виден вовсе.
    for (final p in kPalettes) {
      for (final b in Brightness.values) {
        final app = buildAppTheme(p, b);
        final style = ProfileTheme.themeFor(app).filledButtonTheme.style!;
        expect(style.backgroundColor?.resolve(const {}), app.scheme!.primary,
            reason: '${p.name} (${b.name}): кнопка взяла не цвет темы');
        expect(style.foregroundColor?.resolve(const {}), app.scheme!.onPrimary);
        // Значок на тональной подложке обязан читаться: это и есть выбор типа
        // связи, где иконки пропадали.
        expect(app.scheme!.primaryContainer, isNot(app.scheme!.primary),
            reason: '${p.name} (${b.name}): подложка слилась с акцентом');
      }
    }
  });
}
