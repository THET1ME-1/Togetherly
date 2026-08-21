import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/cycle_entry.dart';
import 'package:love_app/models/mood_vessel.dart';

VesselDay day(int d, {
  bool mine = false,
  bool partner = false,
  bool intimacy = false,
  bool period = false,
  bool partnerPeriod = false,
}) =>
    VesselDay(
      date: DateTime(2026, 8, d),
      mineMood: mine ? const Color(0xFFFF7E8B) : null,
      partnerMood: partner ? const Color(0xFF3B82F6) : null,
      intimacy: intimacy,
      period: period,
      partnerPeriod: partnerPeriod,
    );

void main() {
  group('день сосуда', () {
    test('пустой день не даёт ни одного этажа', () {
      expect(day(1).floors, 0);
      expect(day(1).isEmpty, isTrue);
    });

    test('каждая отметка настроения — свой этаж', () {
      expect(day(1, mine: true).floors, 1);
      expect(day(1, mine: true, partner: true).floors, 2);
    });

    test('близость поднимает блок ещё на этаж', () {
      expect(day(1, mine: true, intimacy: true).floors, 2);
    });

    test('месячные высоту не меняют — это состояние, а не событие', () {
      expect(day(1, mine: true, period: true).floors, 1);
      expect(day(1, period: true).isEmpty, isTrue);
      expect(day(1, mine: true, partnerPeriod: true).floors, 1);
    });

    test('чьи месячные — видно по кромке, а не по одному флагу', () {
      final d = day(1, mine: true, period: true);
      expect(d.period, isTrue);
      expect(d.partnerPeriod, isFalse);
    });

    test('оба отметились — блок общий', () {
      expect(day(1, mine: true, partner: true).who, VesselWho.both);
      expect(day(1, mine: true).who, VesselWho.mine);
      expect(day(1, partner: true).who, VesselWho.partner);
      expect(day(1).who, VesselWho.none);
    });
  });

  group('кладка', () {
    test('блок падает в самый низкий столбец', () {
      final days = [
        day(1, mine: true, partner: true), // 2 этажа → столбец 0
        day(2, mine: true),                // 1 этаж → столбец 1
        day(3, mine: true),                // 1 этаж → столбец 2
      ];
      final blocks = layoutVessel(days, columns: 3);
      expect(blocks.map((b) => b.column), [0, 1, 2]);
      expect(blocks.every((b) => b.bottom == 0), isTrue);
    });

    test('следующий блок ложится поверх лежащего', () {
      final days = [day(1, mine: true), day(2, mine: true)];
      final blocks = layoutVessel(days, columns: 1);
      expect(blocks.last.bottom, 1);
      expect(blocks.last.column, 0);
    });

    test('пропущенный день не занимает места, но оставляет щербину', () {
      final days = [day(1), day(2, mine: true)];
      final blocks = layoutVessel(days, columns: 1);
      expect(blocks, hasLength(1));
      expect(blocks.single.date.day, 2);
      // Щербина считается отдельно: сколько дней месяц потерял.
      expect(vesselGaps(days), 1);
    });

    test('высота кладки — самый высокий столбец', () {
      final days = [
        day(1, mine: true, partner: true),
        day(2, mine: true),
      ];
      expect(vesselHeight(layoutVessel(days, columns: 1)), 3);
    });

    test('порядок дней сохраняется: блок падает после предыдущего', () {
      final days = List.generate(9, (i) => day(i + 1, mine: true));
      final blocks = layoutVessel(days, columns: 3);
      expect(blocks.map((b) => b.date.day), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(blocks.map((b) => b.column), [0, 1, 2, 0, 1, 2, 0, 1, 2]);
    });
  });

  group('сборка из отметок', () {
    test('цикл партнёра берётся только из того, что отдал сервер', () {
      final days = buildVesselDays(
        month: DateTime(2026, 8),
        mineMoods: {},
        partnerMoods: {},
        myCycle: [
          CycleEntry(
            id: 'c1',
            day: DateTime(2026, 8, 4),
            kind: CycleKind.period,
          ),
          CycleEntry(
            id: 'c2',
            day: DateTime(2026, 8, 5),
            kind: CycleKind.intimacy,
          ),
        ],
        partnerCycle: [
          CycleEntry(
            id: 'c3',
            day: DateTime(2026, 8, 6),
            kind: CycleKind.period,
          ),
        ],
      );
      expect(days.firstWhere((d) => d.date.day == 4).period, isTrue);
      expect(days.firstWhere((d) => d.date.day == 5).intimacy, isTrue);
      expect(days.firstWhere((d) => d.date.day == 5).floors, 1);
      expect(days.firstWhere((d) => d.date.day == 6).partnerPeriod, isTrue);
      expect(days.firstWhere((d) => d.date.day == 6).period, isFalse);
    });

    test('в месяце столько дней, сколько в нём есть', () {
      final days = buildVesselDays(
        month: DateTime(2026, 2),
        mineMoods: {},
        partnerMoods: {},
        myCycle: const [],
        partnerCycle: const [],
      );
      expect(days, hasLength(28));
    });
  });

  group('период кладки', () {
    test('неделя — семь блоков, а не весь месяц', () {
      final days = buildVesselRange(
        from: DateTime(2026, 7, 6),
        to: DateTime(2026, 7, 12),
        mineMoods: const {},
        partnerMoods: const {},
        myCycle: const [],
        partnerCycle: const [],
      );
      expect(days.length, 7);
      expect(days.first.date, DateTime(2026, 7, 6));
      expect(days.last.date, DateTime(2026, 7, 12));
    });

    test('месяц — все его дни', () {
      final days = buildVesselRange(
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
        mineMoods: const {},
        partnerMoods: const {},
        myCycle: const [],
        partnerCycle: const [],
      );
      expect(days.length, 31);
    });

    test('год — двенадцать блоков-месяцев, а не 365 дней', () {
      final months = buildVesselYear(
        year: 2026,
        mineMoods: {
          '2026-03-04': const Color(0xFFFF0000),
          '2026-03-05': const Color(0xFFFF0000),
        },
        partnerMoods: const {},
        myCycle: const [],
        partnerCycle: const [],
      );
      expect(months.length, 12);
      expect(months[2].date, DateTime(2026, 3));
      expect(months[2].floors, greaterThan(0), reason: 'март пуст');
      expect(months[0].floors, 0, reason: 'январь без отметок должен быть пуст');
    });

    test('в году высота месяца растёт с числом живых дней', () {
      List<VesselDay> yearWith(int days) => buildVesselYear(
            year: 2026,
            mineMoods: {
              for (var d = 1; d <= days; d++)
                '2026-03-${d.toString().padLeft(2, '0')}':
                    const Color(0xFFFF0000),
            },
            partnerMoods: const {},
            myCycle: const [],
            partnerCycle: const [],
          );
      expect(yearWith(20)[2].floors, greaterThan(yearWith(5)[2].floors));
    });
  });

  group('события дня, кроме настроения', () {
    test('воспоминание — свой этаж', () {
      final plain = VesselDay(date: _day, memories: 0);
      final withMemory = VesselDay(date: _day, memories: 1);
      expect(withMemory.floors, plain.floors + 1);
    });

    test('десять воспоминаний за день не превращают блок в башню', () {
      final many = VesselDay(date: _day, memories: 10);
      expect(many.floors, lessThanOrEqualTo(3));
    });

    test('разговор в чате — свой этаж', () {
      final silent = VesselDay(date: _day);
      final talked = VesselDay(date: _day, chatted: true);
      expect(talked.floors, silent.floors + 1);
    });

    test('день без единого события остаётся щербиной', () {
      final empty = VesselDay(date: _day);
      expect(empty.isEmpty, isTrue);
    });
  });
}

final _day = DateTime(2026, 7, 1);
