import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/together_milestones.dart';
import 'package:love_app/services/locale_service.dart';

/// Дорожка вех виджета «Вместе»: что пройдено, где вы сейчас и что впереди.
///
/// Прежний виджет показывал один процент до ближайшей круглой даты, и считал
/// его натив — вместе с русскими склонениями внутри Kotlin. Дорожка считается
/// здесь, а натив только рисует линию и печатает готовые строки.
void main() {
  final start = DateTime(2026, 5, 12);

  // Сутки прибавляем календарём: Duration(days:) на переводе часов даёт
  // 23-часовые сутки, и «сотый день» уезжает на день назад.
  MilestoneTrack at(int days, {DateTime? anniversary}) => milestoneTrack(
        start: start,
        today: DateTime(start.year, start.month, start.day + days),
        anniversary: anniversary,
      );

  group('ближайшая веха', () {
    test('в первую сотню позади ничего нет', () {
      final t = at(37);
      expect(t.previous, isNull);
      expect(t.next.days, 100);
      expect(t.next.isAnniversary, isFalse);
    });

    test('131 день: позади сотня, впереди двести', () {
      final t = at(131);
      expect(t.previous!.days, 100);
      expect(t.previous!.date, DateTime(2026, 8, 20));
      expect(t.next.days, 200);
      expect(t.next.daysLeft, 69);
    });

    test('процент считается от прошлой вехи до следующей', () {
      expect(at(131).percent, 31);
      expect(at(100).percent, 0);
      expect(at(199).percent, 99);
    });

    test('день самой вехи: она уже позади, впереди следующая', () {
      final t = at(200);
      expect(t.previous!.days, 200);
      expect(t.next.days, 300);
      expect(t.next.daysLeft, 100);
    });
  });

  group('годовщина', () {
    test('перебивает сотню, когда наступает раньше', () {
      // 360-й день: до 400 дней сорок суток, а год исполняется через пять.
      final t = at(360);
      expect(t.next.isAnniversary, isTrue);
      expect(t.next.date, DateTime(2027, 5, 12));
      expect(t.next.daysLeft, 5);
    });

    test('считается календарём, а не делением на 365', () {
      // 2028-й високосный: от 12.05.2027 до 12.05.2028 — 366 суток.
      final t = at(366 + 365);
      expect(t.anniversary.date, DateTime(2028, 5, 12));
      expect(t.anniversary.years, 2);
    });

    test('своя дата из профиля важнее даты начала счёта', () {
      final t = at(131, anniversary: DateTime(2025, 9, 30));
      expect(t.anniversary.date, DateTime(2026, 9, 30));
    });
  });

  group('дорожка целиком', () {
    test('в первый день пути позади пусто, процент нулевой', () {
      final t = at(0);
      expect(t.previous, isNull);
      expect(t.days, 0);
      expect(t.percent, 0);
      expect(t.next.days, 100);
    });

    test('процент не вылезает за края', () {
      for (final d in [0, 1, 99, 100, 364, 365, 366, 1000]) {
        final p = at(d).percent;
        expect(p, inInclusiveRange(0, 100), reason: 'на $d дне процент $p');
      }
    });

    test('дата начала в будущем не ломает счёт', () {
      final t = milestoneTrack(
        start: DateTime(2026, 12, 1),
        today: DateTime(2026, 5, 12),
      );
      expect(t.days, 0);
      expect(t.next.days, 100);
      expect(t.percent, 0);
    });
  });

  group('подписи дорожки', () {
    setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

    String day(DateTime d) => '${d.day}.${d.month}';

    test('строки собираются приложением, а не нативом', () {
      final l = trackLabels(at(131), LocaleService.current, day);
      expect(l.previousTitle, '100 дней');
      expect(l.previousSub, 'Прошли 20.8');
      expect(l.todayTitle, 'Сегодня');
      expect(l.todaySub, '31% пути до 200 дней');
      expect(l.nextTitle, '200 дней');
      expect(l.nextSub, 'через 69 дней');
      expect(l.anniversaryTitle, '1 год');
      expect(l.anniversarySub, '12.5');
    });

    test('в первой сотне строки прошлой вехи пусты, а не «0 дней»', () {
      final l = trackLabels(at(12), LocaleService.current, day);
      expect(l.previousTitle, isEmpty);
      expect(l.previousSub, isEmpty);
      expect(l.nextTitle, '100 дней');
    });

    test('годовщина впереди — она и стоит ближайшей вехой', () {
      final l = trackLabels(at(360), LocaleService.current, day);
      expect(l.nextTitle, '1 год');
      expect(l.nextSub, 'через 5 дней');
    });
  });
}
