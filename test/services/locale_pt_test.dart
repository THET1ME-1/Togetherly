import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/locale_service.dart';

/// Португальский: словарь целиком плюс свои числительные и даты.
///
/// Норма бразильская: обращение на «você». `LocaleService.detect` отправляет в
/// `pt` и `pt-BR`, и `pt-PT` — колонка словаря одна на всех, а говорящих в
/// Бразилии на порядок больше.
void main() {
  late AppStrings pt;

  setUp(() {
    LocaleService.instance.setLanguage(AppLanguage.pt);
    pt = LocaleService.instance.strings;
  });

  test('словарь переведён целиком', () {
    final missing = kStrings.entries
        .where((e) => (e.value['pt'] ?? '').isEmpty)
        .map((e) => e.key)
        .toList();
    expect(missing, isEmpty, reason: 'без португальского: ${missing.take(15)}');
  });

  test('простые строки идут из португальской колонки', () {
    expect(pt.save, 'Salvar');
    expect(pt.memoryLane, 'Mural de lembranças');
    expect(pt.coinBalance, 'Moedas');
  });

  test('ноль во множественном, единица в единственном', () {
    expect(pt.timerDaysCount(0), '0 dias');
    expect(pt.timerDaysCount(1), '1 dia');
    expect(pt.timerDaysCount(9), '9 dias');
    expect(pt.coinsPlus(1), '+1 moeda');
    expect(pt.coinsPlus(8), '+8 moedas');
    expect(pt.memoriesUnit(1), 'lembrança');
    expect(pt.memoriesUnit(2), 'lembranças');
    expect(pt.tgMonthsCaption(1), 'mês');
    expect(pt.tgMonthsCaption(3), 'meses');
  });

  test('даты португальские, первое число — 1º и с предлогом', () {
    expect(pt.fullMonths[3], 'março');
    expect(pt.longWeekdays.first, 'segunda-feira');
    expect(pt.chatDateHeader(DateTime(2001, 3, 1)), '1º de março de 2001');
    expect(pt.chatDateHeader(DateTime(2001, 3, 9)), '9 de março de 2001');
    // В карточку идёт короткая форма без «-feira», иначе строка вдвое длиннее.
    expect(pt.partnerMissPeak(pt.weekdayLong(1)), 'Mais na segunda');
  });

  test('обращение на você, а не tu', () {
    // «tu» дало бы «estás», «tens», «contigo» — так пишут в Португалии.
    final samples = [
      pt.howAreYouFeeling,
      pt.partnerWillSeeMood,
      pt.logoutConfirm,
      pt.chatEmptyGhostMine,
    ];
    for (final s in samples) {
      expect(
        RegExp(r'\b(estás|tens|podes|queres|contigo)\b').hasMatch(s),
        isFalse,
        reason: 'европейская форма в «$s»',
      );
    }
  });
}
