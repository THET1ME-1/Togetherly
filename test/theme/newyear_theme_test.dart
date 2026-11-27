import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/custom_theme.dart';
import 'package:love_app/models/user_data.dart';
import 'package:love_app/models/xmas_tree.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';

/// Тема «Новый год» (27.11.2026): тёмная — цвета зимнего экрана сундука,
/// светлая — красный и белый; за интерфейсом идёт снег и падают снежки.
/// Сезон как у зимнего сундука: открыта всем с 1 декабря по 15 января,
/// потом остаётся у тех, кто её застал.
void main() {
  final ny = kPalettes.firstWhere((p) => p.name == 'Новый год');

  test('тема стоит своим номером и не продаётся', () {
    expect(ny.index, 27);
    expect(kPalettes[27], same(ny));
    expect(ny.isPremium, isFalse);
    expect(ny.price, 0);
    expect(AppThemes.byIndex(27).isPremium, isFalse);
    expect(ny.darkOnly, isFalse);
    expect(ny.badge, isNotNull);
  });

  test('сезон: с 1 декабря по 15 января всем, потом — тем, кто её застал', () {
    final s = ny.season!;
    final before = DateTime.utc(2026, 11, 1);
    final after = DateTime.utc(2027, 1, 20);
    expect(s.openFor(DateTime.utc(2026, 12, 20), DateTime.utc(2026, 12, 21)), isTrue);
    expect(s.openFor(DateTime.utc(2027, 1, 10), DateTime.utc(2027, 1, 15)), isTrue);
    expect(s.openFor(before, DateTime.utc(2027, 3, 1)), isTrue);
    expect(s.openFor(after, DateTime.utc(2027, 3, 1)), isFalse);
    expect(s.openFor(before, DateTime.utc(2026, 11, 28)), isFalse);
  });

  test('тёмная — цвета зимнего сундука, светлая — красный и белый, обе со снегом', () {
    final light = buildAppTheme(ny, Brightness.light);
    final dark = buildAppTheme(ny, Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(light.bgGradient.first, const Color(0xFFFCF0EF));
    expect(light.primary, const Color(0xFFD8413B));
    expect(light.scheme!.secondary, const Color(0xFF1F2B4A));
    expect(dark.brightness, Brightness.dark);
    expect(dark.bgGradient.first, const Color(0xFF16203A));
    expect(dark.cardSurface, const Color(0xFF1F2B4A));
    expect(dark.primary, const Color(0xFFD8413B));
    expect(dark.scheme!.secondary, const Color(0xFF9DB8F0));
    for (final t in [light, dark]) {
      expect(t.bgSnow, isNotNull);
    }
    // На светлом белой снежинке нужна обводка, иначе белое на белом пропадает.
    expect(light.bgSnow!.rim.a, greaterThan(0));
    expect(dark.bgSnow!.rim.a, 0);
  });

  test('в предпросмотре сезона тема видна по дню предпросмотра, а не по настоящему', () {
    // Тестер живёт в 1 декабря (SeasonPreview ставит xtNow), а на часах ноябрь.
    xtNow = () => DateTime(2026, 12, 1, 12);
    addTearDown(() => xtNow = DateTime.now);
    final strip = paletteStripEntries(customCount: 0, plusVisible: false, registeredAt: DateTime.utc(2026, 11, 20));
    expect(strip.any((e) => e.isPalette && e.index == 27), isTrue);
    // и выбрать её можно: выбор проверяется теми же часами
    expect(paletteOpen(kPalettes[27], registeredAt: DateTime.utc(2026, 11, 20), now: UserData.clock()), isTrue);
  });

  test('сочность и AMOLED не теряют снег', () {
    for (final b in Brightness.values) {
      for (final f in SchemeFlavor.values) {
        expect(buildAppTheme(ny, b, flavor: f).bgSnow, isNotNull, reason: '$b $f');
      }
    }
  });
}
