import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/together_caption.dart';
import 'package:love_app/models/year_progress.dart';
import 'package:love_app/services/locale_service.dart';

/// Подпись «сколько уже вместе» на виджете «Дней вместе».
///
/// Жалоба со снимком экрана 15.08.2026: пара вместе 348 дней, а виджет пишет
/// «0 лет уже ❤️» — человек обвёл эту строку красным и назвал поломкой
/// счётчика. Ноль лет — правда, но говорить его вслух незачем: у пары, которая
/// не дожила до первой годовщины, счёт идёт на месяцы.
void main() {
  late AppStrings ru;
  late AppStrings en;

  setUp(() {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    ru = LocaleService.instance.strings;
    LocaleService.instance.setLanguage(AppLanguage.en);
    en = LocaleService.instance.strings;
  });

  YearProgress progress(String start, String now) => YearProgress.between(
        DateTime.parse(start),
        DateTime.parse(now),
      );

  test('до первой годовщины считаем месяцами, а не нулём лет', () {
    // Ровно случай со снимка: 01.09.2025 → 15.08.2026, 348 дней.
    final p = progress('2025-09-01', '2026-08-15');
    expect(p.yearsCompleted, 0);
    expect(p.monthsCompleted, 11);
    expect(togetherAlreadyCaption(p, ru), '11 месяцев уже ❤️');
    expect(togetherAlreadyCaption(p, en), '11 months already ❤️');
  });

  test('после годовщины считаем годами', () {
    final p = progress('2024-09-01', '2026-08-15');
    expect(p.yearsCompleted, 1);
    expect(togetherAlreadyCaption(p, ru), '1 год уже ❤️');
  });

  test('в первый месяц строки нет вовсе', () {
    // Число дней и так стоит крупно в середине виджета: «0 месяцев уже»
    // читалось бы такой же поломкой, как «0 лет уже».
    final p = progress('2026-08-01', '2026-08-15');
    expect(p.monthsCompleted, 0);
    expect(togetherAlreadyCaption(p, ru), '');
  });

  test('склонения русских месяцев', () {
    expect(togetherAlreadyCaption(progress('2026-07-10', '2026-08-15'), ru),
        '1 месяц уже ❤️');
    expect(togetherAlreadyCaption(progress('2026-05-10', '2026-08-15'), ru),
        '3 месяца уже ❤️');
    expect(togetherAlreadyCaption(progress('2025-10-10', '2026-08-15'), ru),
        '10 месяцев уже ❤️');
  });

  test('дата в будущем не даёт отрицательных подписей', () {
    final p = progress('2027-01-01', '2026-08-15');
    expect(togetherAlreadyCaption(p, ru), '');
  });
}
