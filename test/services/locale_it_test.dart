import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/locale_service.dart';

/// Итальянский: словарь целиком плюс свои числительные и даты.
///
/// Порог множественного как в испанском (`== 1`), а не как во французском:
/// «0 giorni», «1 giorno», «2 giorni». Первое число месяца пишется «1º».
void main() {
  late AppStrings it;

  setUp(() {
    LocaleService.instance.setLanguage(AppLanguage.it);
    it = LocaleService.instance.strings;
  });

  test('словарь переведён целиком', () {
    final missing = kStrings.entries
        .where((e) => (e.value['it'] ?? '').isEmpty)
        .map((e) => e.key)
        .toList();
    expect(missing, isEmpty, reason: 'без итальянского: ${missing.take(15)}');
  });

  test('простые строки идут из итальянской колонки', () {
    expect(it.save, 'Salva');
    expect(it.memoryLane, 'Diario dei ricordi');
    expect(it.coinBalance, 'Monete');
  });

  test('ноль во множественном, единица в единственном', () {
    expect(it.timerDaysCount(0), '0 giorni');
    expect(it.timerDaysCount(1), '1 giorno');
    expect(it.timerDaysCount(6), '6 giorni');
    expect(it.coinsPlus(1), '+1 moneta');
    expect(it.coinsPlus(4), '+4 monete');
    expect(it.memoriesUnit(1), 'ricordo');
    expect(it.memoriesUnit(3), 'ricordi');
    // Foto — существительное неизменяемое: одна форма на оба числа.
    expect(it.photosUnit(1), 'foto');
    expect(it.photosUnit(5), 'foto');
  });

  test('даты итальянские, первое число — 1º', () {
    expect(it.fullMonths[5], 'maggio');
    expect(it.longWeekdays.first, 'lunedì');
    expect(it.chatDateHeader(DateTime(2001, 3, 1)), '1º marzo 2001');
    expect(it.chatDateHeader(DateTime(2001, 3, 9)), '9 marzo 2001');
    // Артикль внутри строки: «Più spesso il lunedì», у воскресенья — «la».
    expect(it.partnerMissPeak(it.weekdayLong(1)), 'Più spesso il lunedì');
    expect(it.weekdayLong(7), 'la domenica');
  });

  test('апостроф типографский', () {
    for (final s in [it.registrationError('x'), it.exportError('y')]) {
      expect(s.contains("'"), isFalse, reason: 'машинный апостроф в «$s»');
    }
  });
}
