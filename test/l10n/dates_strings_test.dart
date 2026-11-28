import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/l10n/dates_text.dart';
import 'package:love_app/l10n/dict/dates.dart';
import 'package:love_app/l10n/uk/dates.dart';
import 'package:love_app/l10n/zh/dates.dart';
import 'package:love_app/models/pair_date.dart';
import 'package:love_app/services/locale_service.dart';

/// «Наши даты» говорят на всех девяти языках: пропавший перевод показал бы
/// английский посреди русского экрана.
void main() {
  const langs = ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de'];

  test('каждая строка есть на семи языках словаря', () {
    final gaps = [
      for (final e in datesStrings.entries)
        for (final l in langs)
          if ((e.value[l] ?? '').trim().isEmpty && e.key != 'dt.and') '${e.key}:$l',
    ];
    expect(gaps, isEmpty);
  });

  test('украинский и китайский покрывают все ключи и ничего лишнего', () {
    expect(datesUk.keys.toSet(), datesStrings.keys.toSet());
    expect(datesZh.keys.toSet(), datesStrings.keys.toSet());
  });

  test('метки подстановки совпадают во всех переводах', () {
    final re = RegExp(r'\{(\w+)\}');
    for (final e in datesStrings.entries) {
      final want = re.allMatches(e.value['ru']!).map((m) => m[1]).toSet();
      for (final l in langs) {
        expect(re.allMatches(e.value[l]!).map((m) => m[1]).toSet(), want, reason: '${e.key}:$l');
      }
      expect(re.allMatches(datesUk[e.key]!).map((m) => m[1]).toSet(), want, reason: '${e.key}:uk');
      expect(re.allMatches(datesZh[e.key]!).map((m) => m[1]).toSet(), want, reason: '${e.key}:zh');
    }
  });

  test('у каждого числа три формы', () {
    // Дни недели и порядковые тоже кончаются цифрой, но это не формы числа.
    const byIndex = {'dt.onWd', 'dt.nthWd', 'dt.lastWd', 'dt.ord'};
    final bases = {
      for (final k in datesStrings.keys)
        if (RegExp(r'\.[125]$').hasMatch(k)) k.substring(0, k.length - 2),
    }.difference(byIndex);
    for (final b in bases) {
      for (final f in ['1', '2', '5']) {
        expect(datesStrings.containsKey('$b.$f'), isTrue, reason: '$b.$f');
      }
    }
  });

  test('подсказки — одно предложение', () {
    for (final k in ['dt.phHint', 'dt.phSync', 'dt.emptyHint']) {
      final ru = datesStrings[k]!['ru']!;
      expect(RegExp(r'[.!?](\s|$)').allMatches(ru).length, 1, reason: k);
    }
  });

  group('по-русски', () {
    setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));
    final sunday = DateTime(2026, 11, 8);
    final thursday = DateTime(2026, 11, 26);

    test('пресеты повтора', () {
      expect(repeatText('', sunday), ('Не повторяется', ''));
      expect(repeatText('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', sunday), ('По будням', 'пн–пт'));
      expect(repeatText('FREQ=WEEKLY;BYDAY=SU', sunday), ('Каждую неделю', 'в воскресенье'));
      expect(repeatText('FREQ=MONTHLY;BYMONTHDAY=8', sunday), ('Каждый месяц', '8-го числа'));
      expect(repeatText('FREQ=MONTHLY;BYDAY=2SU', sunday), ('Каждый месяц', '2-е воскресенье'));
      expect(repeatText('FREQ=MONTHLY;BYDAY=-1TH', thursday), ('Каждый месяц', 'последний четверг'));
      expect(repeatText('FREQ=YEARLY', sunday), ('Каждый год', '8 ноября'));
    });

    test('своё правило целиком', () {
      expect(repeatText('FREQ=WEEKLY;BYDAY=WE,SU;UNTIL=20261215', sunday),
          ('Каждую неделю', 'в ср и вс, до 15 декабря'));
      expect(repeatText('FREQ=WEEKLY;INTERVAL=3;BYDAY=SU;COUNT=4', sunday),
          ('Каждые 3 недели', 'в воскресенье, 4 раза'));
      expect(repeatText('FREQ=DAILY;INTERVAL=21', sunday), ('Каждый 21 день', ''));
      expect(repeatText('FREQ=YEARLY;INTERVAL=5', sunday), ('Каждые 5 лет', '8 ноября'));
    });

    test('напоминания', () {
      expect(reminderText(-540, allDay: true), 'В этот день в 9:00');
      expect(reminderText(900, allDay: true), 'За день в 9:00');
      expect(reminderText(2340, allDay: true), 'За 2 дня в 9:00');
      expect(reminderText(9540, allDay: true), 'За неделю в 9:00');
      expect(reminderText(42660, allDay: true), 'За месяц в 9:00');
      expect(reminderText(3120, allDay: true), 'За 3 дня в 20:00');
      expect(reminderText(0, allDay: false), 'В момент начала');
      expect(reminderText(30, allDay: false), 'За 30 минут');
      expect(reminderText(60, allDay: false), 'За час');
      expect(reminderText(120, allDay: false), 'За 2 часа');
      expect(reminderText(1440, allDay: false), 'За день');
      expect(reminderText(21, allDay: false), 'За 21 минуту');
    });

    test('сколько осталось', () {
      expect(untilText(0), 'Сегодня');
      expect(untilText(1), 'Завтра');
      expect(untilText(6), 'через 6 дней');
      expect(untilText(22), 'через 22 дня');
    });

    test('название готовой даты', () {
      final a = autoDates(start: DateTime(2024, 12, 10), birthdays: const {}, myUid: 'me', names: const {}).single;
      expect(dateTitle(a, DateTime(2026, 12, 10)), '2 года вместе');
      expect(dateTitle(a, DateTime(2029, 12, 10)), '5 лет вместе');
    });
  });

  group('по-английски', () {
    setUp(() => LocaleService.instance.setLanguage(AppLanguage.en));
    tearDown(() => LocaleService.instance.setLanguage(AppLanguage.ru));

    test('повтор и напоминание', () {
      expect(repeatText('FREQ=MONTHLY;BYDAY=2SU', DateTime(2026, 11, 8)), ('Every month', '2nd Sunday'));
      expect(reminderText(900, allDay: true), 'The day before at 9:00');
      expect(untilText(6), 'in 6 days');
    });
  });
}
