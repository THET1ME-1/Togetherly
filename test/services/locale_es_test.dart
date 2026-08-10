import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/locale_service.dart';

/// Испанский: словарь целиком плюс свои числительные и даты.
///
/// Главное отличие от французского: ноль требует множественного числа
/// («0 días», но «1 día»), поэтому порог в хелпере `_n` — `== 1`, а не `<= 1`.
/// Месяцы и дни недели пишутся со строчной — это норма языка.
void main() {
  late AppStrings es;

  setUp(() {
    LocaleService.instance.setLanguage(AppLanguage.es);
    es = LocaleService.instance.strings;
  });

  test('словарь переведён целиком', () {
    final missing = kStrings.entries
        .where((e) => (e.value['es'] ?? '').isEmpty)
        .map((e) => e.key)
        .toList();
    expect(missing, isEmpty, reason: 'без испанского: ${missing.take(15)}');
  });

  test('простые строки идут из испанской колонки', () {
    expect(es.save, 'Guardar');
    expect(es.memoryLane, 'Muro de recuerdos');
    expect(es.coinBalance, 'Monedas');
  });

  test('ноль во множественном числе, единица в единственном', () {
    expect(es.timerDaysCount(0), '0 días');
    expect(es.timerDaysCount(1), '1 día');
    expect(es.timerDaysCount(4), '4 días');
    expect(es.coinsPlus(1), '+1 moneda');
    expect(es.coinsPlus(3), '+3 monedas');
    expect(es.photosUnit(0), 'fotos');
    expect(es.photosUnit(1), 'foto');
    expect(es.memoriesUnit(2), 'recuerdos');
  });

  test('даты испанские и со строчной буквы', () {
    expect(es.fullMonths[1], 'enero');
    expect(es.longWeekdays.first, 'lunes');
    expect(es.shortWeekdays[5], 'sáb');
    // Дата пишется с предлогом: «8 de marzo de 2001».
    expect(es.chatDateHeader(DateTime(2001, 3, 8)), '8 de marzo de 2001');
    // Артикль внутри строки: «Sobre todo los lunes».
    expect(es.partnerMissPeak(es.weekdayLong(1)), 'Sobre todo los lunes');
  });

  test('вопросы и восклицания парные', () {
    expect(es.howAreYouFeeling, startsWith('¿'));
    expect(es.howAreYouFeeling, endsWith('?'));
    expect(es.chatDeleteConfirm('x'), startsWith('¿'));
    expect(es.reflectionQuestions.first, startsWith('¿'));
    final bang = es.moodRecorded('Alegría');
    expect(bang, startsWith('¡'));
    expect(bang, endsWith('!'));
  });
}
