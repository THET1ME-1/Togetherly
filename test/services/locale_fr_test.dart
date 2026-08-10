import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/locale_service.dart';

/// Французский: словарь целиком плюс свои числительные и даты.
///
/// Два правила языка, которых нет в немецком. Единственное число берут и ноль,
/// и единица («0 jour», «1 jour», «2 jours»). Первое число месяца пишется
/// «1er», остальные обычными цифрами.
void main() {
  late AppStrings fr;

  setUp(() {
    LocaleService.instance.setLanguage(AppLanguage.fr);
    fr = LocaleService.instance.strings;
  });

  test('словарь переведён целиком', () {
    final missing = kStrings.entries
        .where((e) => (e.value['fr'] ?? '').isEmpty)
        .map((e) => e.key)
        .toList();
    expect(missing, isEmpty, reason: 'без французского: ${missing.take(15)}');
  });

  test('простые строки идут из французской колонки', () {
    expect(fr.save, 'Enregistrer');
    expect(fr.memoryLane, 'Fil des souvenirs');
    expect(fr.coinBalance, 'Pièces');
  });

  test('ноль и единица берут единственное число', () {
    expect(fr.timerDaysCount(0), '0 jour');
    expect(fr.timerDaysCount(1), '1 jour');
    expect(fr.timerDaysCount(2), '2 jours');
    expect(fr.coinsPlus(1), '+1 pièce');
    expect(fr.coinsPlus(5), '+5 pièces');
    expect(fr.photosUnit(0), 'photo');
    expect(fr.photosUnit(3), 'photos');
    expect(fr.tgInDays(1), 'dans 1 jour');
  });

  test('первое число месяца пишется 1er', () {
    expect(fr.chatDateHeader(DateTime(2001, 3, 1)), '1er mars 2001');
    expect(fr.chatDateHeader(DateTime(2001, 3, 8)), '8 mars 2001');
    expect(fr.dayLogDate(DateTime(2026, 5, 1)), startsWith('1er '));
  });

  test('даты и дни недели французские', () {
    expect(fr.fullMonths[8], 'août');
    expect(fr.longWeekdays.first, 'lundi');
    // Артикль внутри строки: фраза собирается как «Le plus souvent le lundi».
    expect(fr.partnerMissPeak(fr.weekdayLong(1)), 'Le plus souvent le lundi');
  });

  test('апостроф типографский, а не машинный', () {
    // Прямой апостроф в Dart-литерале пришлось бы экранировать, и он же
    // выглядит чужеродно во французском тексте.
    final samples = [fr.registrationError('x'), fr.capsuleOpensIn(0)];
    for (final s in samples) {
      expect(s.contains("'"), isFalse, reason: 'машинный апостроф в «$s»');
    }
  });
}
