import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';

/// Кружок в ленте палитр — это четыре квадранта M3-схемы. Он обязан, во-первых,
/// показывать ту же схему, что достанется экрану, и во-вторых, отличаться от
/// соседей: две одинаковые кнопки в ряду читаются как «темы задвоились».
///
/// До 11 августа 2026 кружок считал вариант схемы только по насыщенности и
/// игнорировал вариант самой палитры. «Монохром» объявлен `neutral`, но
/// рисовался через `tonalSpot` — и совпадал с «Нордиком» до пикселя во всех
/// четырёх квадрантах.
void main() {
  String quadrantsOf(Palette p, SchemeFlavor flavor) {
    final s = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: Brightness.light,
      dynamicSchemeVariant: variantOf(p, flavor),
    );
    return [
      s.primaryContainer,
      s.primary,
      s.tertiaryContainer,
      s.tertiary,
    ].map((c) => c.toARGB32().toRadixString(16)).join('|');
  }

  for (final flavor in SchemeFlavor.values) {
    test('кружки палитр различимы: ${flavor.name}', () {
      final seen = <String, String>{};
      for (final p in kPalettes) {
        final key = quadrantsOf(p, flavor);
        final twin = seen[key];
        expect(
          twin,
          isNull,
          reason: 'кружки «${p.name}» и «$twin» совпадают целиком',
        );
        seen[key] = p.name;
      }
      expect(seen.length, kPalettes.length);
    });
  }

  test('вариант палитры уточняет только мягкую насыщенность', () {
    final mono = kPalettes.firstWhere((p) => p.name == 'Монохром');

    expect(variantOf(mono, SchemeFlavor.soft), mono.variant);
    expect(variantOf(mono, SchemeFlavor.juicy), SchemeFlavor.juicy.variant);
    expect(variantOf(mono, SchemeFlavor.exact), SchemeFlavor.exact.variant);
  });
}
