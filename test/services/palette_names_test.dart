import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/l10n/palette_names.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';

/// Имя готовой палитры на языке человека. До 19.10.2026 список имён жил
/// внутри профиля, а шапка предпросмотра на главной писала внутреннее
/// русское имя (`AppTheme.name`) всем языкам подряд.
void main() {
  tearDown(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  test('у каждой палитры своё имя на каждом языке', () {
    for (final lang in AppLanguage.values) {
      LocaleService.instance.setLanguage(lang);
      final names = [for (final p in kPalettes) paletteDisplayName(p.index)];
      expect(names.where((n) => n.trim().isEmpty), isEmpty, reason: lang.name);
      expect(names.toSet().length, kPalettes.length,
          reason: '${lang.name}: имена совпали — ${names.join(', ')}');
    }
  });

  test('«Хэллоуин» называется по-человечески', () {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    expect(paletteDisplayName(25), 'Хэллоуин');
    LocaleService.instance.setLanguage(AppLanguage.en);
    expect(paletteDisplayName(25), 'Halloween');
  });

  test('чужой номер даёт имя палитры по умолчанию', () {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    expect(paletteDisplayName(-1), paletteDisplayName(0));
    expect(paletteDisplayName(999), paletteDisplayName(0));
  });
}
