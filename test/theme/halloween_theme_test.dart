import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/utils/readable_text.dart';

/// Тема «Хэллоуин» (макет «Б. Узор», выбор владельца 19.10.2026): ночь со
/// страницы хэллоуинского сундука, тыквенная заливка, сиреневый второй цвет
/// и контуры предметов праздника одним цветом по фону, как обои в чате.
void main() {
  final hw = kPalettes.firstWhere((p) => p.name == 'Хэллоуин');
  const page = Color(0xFF1E1729);

  test('тема стоит своим номером и продаётся как прочие', () {
    // Номер — ключ владения на сервере (`owned_themes`), его не двигают.
    expect(hw.index, 25);
    expect(kPalettes[25], same(hw));
    expect(hw.isPremium, isTrue);
    // Цену называет сервер: `purchase-theme` берёт 30 со всех, кроме 16-й.
    expect(hw.price, 30);
  });

  test('светлой версии нет: в любом режиме и с AMOLED — ночь сундука', () {
    expect(hw.darkOnly, isTrue);
    for (final b in Brightness.values) {
      for (final amoled in [false, true]) {
        final t = buildAppTheme(hw, b, amoled: amoled);
        final why = '${b.name}, AMOLED $amoled';
        expect(t.brightness, Brightness.dark, reason: why);
        expect(t.bgGradient.first, page, reason: why);
        expect(t.cardSurface, const Color(0xFF2C2238), reason: why);
        expect(t.textPrimary, const Color(0xFFF3E9F7), reason: why);
        expect(t.textSecondary, const Color(0xFFBFAFCC), reason: why);
      }
    }
  });

  test('заливка — тыква, надпись поверх читается', () {
    final t = buildAppTheme(hw, Brightness.dark);
    expect(t.fillColor, const Color(0xFFF0924A));
    final ink = AppThemes.onColor(t.fillColor, mode: t.brightness);
    expect(contrastRatio(ink, t.fillColor), greaterThanOrEqualTo(4.5));
  });

  test('сочность крутит тыкву, а ночь и узор остаются', () {
    for (final f in SchemeFlavor.values) {
      final t = buildAppTheme(hw, Brightness.dark, flavor: f);
      expect(t.bgGradient.first, page, reason: f.name);
      expect(t.bgPattern, isNotNull, reason: f.name);
      expect(t.scheme!.surface, page, reason: f.name);
      final ink = AppThemes.onColor(t.fillColor, mode: t.brightness);
      expect(contrastRatio(ink, t.fillColor), greaterThanOrEqualTo(4.5),
          reason: f.name);
      // Значок, а не надпись: норма WCAG 1.4.11 для значков — 3:1.
      expect(contrastRatio(t.navActiveIcon, t.navActiveBg),
          greaterThanOrEqualTo(3.0),
          reason: '${f.name}: значок активной вкладки');
    }
  });

  test('второй цвет сиреневый, поверхности схемы — ночь, а не тыква', () {
    final s = buildAppTheme(hw, Brightness.dark).scheme!;
    expect(s.brightness, Brightness.dark);
    expect(s.secondary, const Color(0xFFC3A3EE));
    expect(s.onSecondary, const Color(0xFF2A1840));
    expect(s.surface, page);
    expect(s.surfaceContainer, const Color(0xFF2C2238));
    expect(s.surfaceContainerHigh, const Color(0xFF382B47));
    expect(s.onSurface, const Color(0xFFF3E9F7));
    expect(s.onSurfaceVariant, const Color(0xFFBFAFCC));
    // Пары «надпись — подложка» обязаны читаться так же, как у прочих тем.
    final pairs = {
      'primary': (s.onPrimary, s.primary),
      'primaryContainer': (s.onPrimaryContainer, s.primaryContainer),
      'secondary': (s.onSecondary, s.secondary),
      'secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
      'tertiaryContainer': (s.onTertiaryContainer, s.tertiaryContainer),
      'surface': (s.onSurface, s.surface),
      'surfaceVariant': (s.onSurfaceVariant, s.surfaceContainerHighest),
    };
    for (final e in pairs.entries) {
      expect(contrastRatio(e.value.$1, e.value.$2), greaterThanOrEqualTo(4.5),
          reason: e.key);
    }
  });

  test('узор есть только у «Хэллоуина»', () {
    for (final p in kPalettes) {
      for (final b in Brightness.values) {
        final t = buildAppTheme(p, b);
        if (identical(p, hw)) {
          expect(t.bgPattern, isNotNull);
        } else {
          expect(t.bgPattern, isNull, reason: '${p.name} (${b.name})');
        }
      }
    }
  });

  test('узор виден на ночи, а текст поверх него читается', () {
    final t = buildAppTheme(hw, Brightness.dark);
    final line = Color.alphaBlend(t.bgPattern!.tint, page);
    expect(contrastRatio(line, page), greaterThan(1.3),
        reason: 'контуры пропадают на фоне');
    expect(contrastRatio(t.textPrimary, line), greaterThanOrEqualTo(7));
    expect(contrastRatio(t.textSecondary, line), greaterThanOrEqualTo(4.5));
  });

  test('картинки темы лежат в сборке', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = [
      buildAppTheme(hw, Brightness.dark).bgPattern!.asset,
      hw.badge!.asset,
    ];
    for (final asset in assets) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
      final dir = asset.substring(0, asset.lastIndexOf('/') + 1);
      expect(pubspec, contains('- $dir'), reason: dir);
    }
  });
}
