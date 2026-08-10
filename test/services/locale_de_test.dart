import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';

/// Немецкий как первый полностью наполненный язык.
///
/// Словарь закрывает 1419 простых строк, но 185 фраз собираются кодом:
/// подстановки, числительные и списки дат. Немецкий отличает 1 Tag от 2 Tage,
/// и если реализацию забыть, немец увидит английское «2 days» посреди
/// немецкого экрана — на глаз это заметно не сразу, тест ловит сразу.
void main() {
  late AppStrings de;
  late AppStrings en;

  setUp(() {
    LocaleService.instance.setLanguage(AppLanguage.de);
    de = LocaleService.instance.strings;
    LocaleService.instance.setLanguage(AppLanguage.en);
    en = LocaleService.instance.strings;
  });

  test('простые строки берутся из немецкой колонки словаря', () {
    expect(de.save, 'Speichern');
    expect(de.cancel, 'Abbrechen');
    expect(de.memoryLane, 'Erinnerungspfad');
    expect(de.coinBalance, 'Münzen');
  });

  test('числительные согласованы: Tag против Tage', () {
    expect(de.timerDaysCount(1), '1 Tag');
    expect(de.timerDaysCount(3), '3 Tage');
    expect(de.waitingDaysLeft(1), '1 Tag');
    expect(de.waitingDaysLeft(12), '12 Tage');
    expect(de.cycleDaysValue(1), '1 Tag');
    expect(de.cycleDaysValue(5), '5 Tage');
    expect(de.tgInDays(1), 'in 1 Tag');
    expect(de.tgInDays(4), 'in 4 Tagen');
    expect(de.coinsPlus(1), '+1 Münze');
    expect(de.coinsPlus(7), '+7 Münzen');
    expect(de.photosUnit(1), 'Foto');
    expect(de.photosUnit(2), 'Fotos');
    expect(de.memoriesUnit(1), 'Erinnerung');
    expect(de.memoriesUnit(9), 'Erinnerungen');
  });

  test('месяцы и дни недели немецкие', () {
    expect(de.fullMonths[3], 'März');
    expect(de.shortMonths[11], 'Dez');
    expect(de.longWeekdays.first, 'Montag');
    expect(de.shortWeekdays, ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']);
    // Наречие, а не название: строка встаёт в «Am häufigsten montags».
    expect(de.partnerMissPeak(de.weekdayLong(1)), 'Am häufigsten montags');
  });

  test('подстановки не теряют значения', () {
    expect(de.partnerIsMood('Anna', 'froh'), 'Anna ist froh');
    expect(de.capsuleFrom('Max'), 'von Max');
    expect(de.watchWithPartner('Max'), 'Mit Max schauen');
    expect(de.shareInviteText('4F2K9C', 'https://t.dy/x'), contains('4F2K9C'));
    expect(
      de.shareInviteText('4F2K9C', 'https://t.dy/x'),
      contains('https://t.dy/x'),
    );
    // Дата в шапке чата: год добавляется через ${}, иначе в строку попадал
    // весь объект DateTime.
    final header = de.chatDateHeader(DateTime(2001, 3, 8));
    expect(header, '8. März 2001');
    expect(header, isNot(contains('00:00')));
  });

  test('ни одна немецкая фраза не осталась английской там, где текст свой', () {
    // Выборка методов с настоящим текстом: если реализация не переопределена,
    // немецкая строка совпадёт с английской.
    final samples = <String, bool>{
      'loginError': de.loginError('x') != en.loginError('x'),
      'memoryTypeName':
          de.memoryTypeName('photo') != en.memoryTypeName('photo'),
      'drawBackgroundName':
          de.drawBackgroundName('grid') != en.drawBackgroundName('grid'),
      'intervalLabel': de.intervalLabel(60) != en.intervalLabel(60),
      'groupOf': de.groupOf(2) != en.groupOf(2),
      'quietPartnerTitle':
          de.quietPartnerTitle('Anna', 2) != en.quietPartnerTitle('Anna', 2),
      'giftIncomingCount': de.giftIncomingCount(2) != en.giftIncomingCount(2),
      'deleteCanvasesTitle':
          de.deleteCanvasesTitle(3) != en.deleteCanvasesTitle(3),
    };
    final english = samples.entries.where((e) => !e.value).map((e) => e.key);
    expect(
      english,
      isEmpty,
      reason: 'осталось по-английски: ${english.join(', ')}',
    );
  });
}
