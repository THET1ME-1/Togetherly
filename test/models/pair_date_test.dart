import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_date.dart';

PairDate _date(Map<String, dynamic> extra) => PairDate.fromMap({
      'id': 'd1',
      'group_id': 'g1',
      'author_uid': 'u1',
      'title': 'Первое свидание',
      'symbol': 'favorite',
      'note': '',
      'day': '2025-11-08',
      'start_time': '',
      'tz': 'Europe/Moscow',
      'rrule': 'FREQ=YEARLY',
      'exdates': <String>[],
      'reminders': [900, -540],
      ...extra,
    });

void main() {
  test('запись туда и обратно', () {
    final d = _date({'start_time': '19:30', 'exdates': ['2026-11-08'], 'reminders': ['900', 30]});
    expect(d.allDay, isFalse);
    expect(d.time, '19:30');
    expect(d.reminders, [30, 900]);
    expect(d.exdates, {'2026-11-08'});
    final map = d.toMap();
    expect(map['day'], '2025-11-08');
    expect(map['start_time'], '19:30');
    expect(map['reminders'], [30, 900]);
    expect(map['exdates'], ['2026-11-08']);
    expect(PairDate.fromMap(map).toMap(), map);
  });

  test('битое время и день не роняют разбор', () {
    final d = _date({'start_time': '25:99', 'day': 'мусор'});
    expect(d.allDay, isTrue);
    expect(d.day, isNull);
    expect(d.occurrencesBetween(DateTime(2020), DateTime(2030)), isEmpty);
  });

  test('каждый год: дни в окне', () {
    final days = _date({})
        .occurrencesBetween(DateTime(2026, 1, 1), DateTime(2027, 12, 31))
        .map((o) => o.day)
        .toList();
    expect(days, [DateTime(2026, 11, 8), DateTime(2027, 11, 8)]);
  });

  test('со временем: момент в поясе автора, день — по часам телефона', () {
    final d = _date({'day': '2026-12-04', 'start_time': '19:00', 'rrule': ''});
    final occ = d.occurrencesBetween(DateTime(2026, 12, 1), DateTime(2026, 12, 10)).single;
    // 19:00 по Москве (+3) — 16:00 UTC при любом поясе телефона.
    expect(occ.at!.toUtc(), DateTime.utc(2026, 12, 4, 16));
    final local = DateTime.utc(2026, 12, 4, 16).toLocal();
    expect(occ.day, DateTime(local.year, local.month, local.day));
  });

  test('ближайший повтор: сегодняшняя дата на весь день ещё впереди', () {
    final d = _date({'day': '2025-11-28'});
    final next = d.nextFrom(DateTime(2026, 11, 28, 22, 0))!;
    expect(next.day, DateTime(2026, 11, 28));
  });

  test('ближайший повтор: прошедшее со временем сегодня уже не ближайшее', () {
    final d = _date({'day': '2026-11-28', 'start_time': '10:00', 'tz': '', 'rrule': 'FREQ=DAILY'});
    final next = d.nextFrom(DateTime(2026, 11, 28, 12, 0))!;
    expect(next.day, DateTime(2026, 11, 29));
  });

  test('выброшенный день пропускается', () {
    final d = _date({'exdates': ['2026-11-08']});
    expect(d.nextFrom(DateTime(2026, 1, 1))!.day, DateTime(2027, 11, 8));
  });

  test('без повтора в прошлом ближайшего нет', () {
    expect(_date({'rrule': '', 'day': '2026-01-01'}).nextFrom(DateTime(2026, 11, 28)), isNull);
  });

  group('все даты пары', () {
    final concert = _date({'id': 'c', 'day': '2026-12-04', 'start_time': '19:00', 'rrule': ''});
    final firstDate = _date({'id': 'f'});
    final weekly = _date({'id': 'w', 'day': '2026-11-01', 'rrule': 'FREQ=WEEKLY'});

    test('ближайшие по порядку, по одному повтору на дату', () {
      final next = upcomingOccurrences([concert, firstDate, weekly], DateTime(2026, 11, 28, 12));
      expect(next.map((o) => o.date.id), ['w', 'c', 'f']);
      expect(next.first.day, DateTime(2026, 11, 29));
    });

    test('по дням окна', () {
      final byDay = occurrencesByDay([concert, firstDate, weekly], DateTime(2026, 11, 1), DateTime(2026, 11, 30));
      expect(byDay.keys, containsAll(['2026-11-01', '2026-11-08', '2026-11-29']));
      expect(byDay['2026-11-08']!.map((o) => o.date.id), unorderedEquals(['f', 'w']));
      expect(byDay.containsKey('2026-12-04'), isFalse);
    });
  });

  group('удаление повтора', () {
    test('только этот день: день выбрасывается, повтор остаётся', () {
      final d = _date({}).skipping(DateTime(2026, 11, 8));
      expect(d.exdates, {'2026-11-08'});
      expect(d.nextFrom(DateTime(2026, 1, 1))!.day, DateTime(2027, 11, 8));
    });

    test('этот и следующие: повтор кончается накануне', () {
      final d = _date({'rrule': 'FREQ=YEARLY;COUNT=10'}).endingBefore(DateTime(2027, 11, 8))!;
      expect(d.rrule, 'FREQ=YEARLY;UNTIL=20271107');
      expect(d.occurrencesBetween(DateTime(2025, 1, 1), DateTime(2030, 1, 1)).map((o) => o.day),
          [DateTime(2025, 11, 8), DateTime(2026, 11, 8)]);
    });

    test('этот и следующие с первого дня — удалить всю дату', () {
      expect(_date({}).endingBefore(DateTime(2025, 11, 8)), isNull);
    });
  });

  group('готовые даты', () {
    test('годовщина пары: со второго года, с числом лет', () {
      final auto = autoDates(
        start: DateTime(2024, 12, 10),
        birthdays: const {},
        myUid: 'me',
        names: const {},
      );
      final anniversary = auto.single;
      expect(anniversary.autoKind, AutoDateKind.anniversary);
      final occs = anniversary.occurrencesBetween(DateTime(2024, 1, 1), DateTime(2026, 12, 31));
      expect(occs.map((o) => o.day), [DateTime(2025, 12, 10), DateTime(2026, 12, 10)]);
      expect(anniversary.yearsAt(occs.last.day), 2);
    });

    test('дни рождения обоих: свой отмечен', () {
      final auto = autoDates(
        start: null,
        birthdays: {'me': DateTime(1999, 3, 2), 'her': DateTime(2000, 1, 17)},
        myUid: 'me',
        names: const {'her': 'Лиза'},
      );
      expect(auto.length, 2);
      final mine = auto.firstWhere((d) => d.subjectUid == 'me');
      final hers = auto.firstWhere((d) => d.subjectUid == 'her');
      expect(mine.autoKind, AutoDateKind.birthday);
      expect(mine.isMine, isTrue);
      expect(hers.subjectName, 'Лиза');
      expect(hers.nextFrom(DateTime(2026, 11, 28))!.day, DateTime(2027, 1, 17));
    });
  });
}
