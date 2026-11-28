import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_date.dart';
import 'package:love_app/models/phone_calendar_plan.dart';

PairDate _d(String id, {String title = 'Дата', String rrule = 'FREQ=YEARLY'}) => PairDate.fromMap({
      'id': id,
      'title': title,
      'day': '2025-11-08',
      'start_time': '',
      'tz': 'Europe/Moscow',
      'rrule': rrule,
      'reminders': [900],
    });

void main() {
  test('новые создаются, исчезнувшие убираются, правленые заменяются', () {
    final a = _d('a'), b = _d('b'), c = _d('c', title: 'Новое имя');
    final plan = phoneCalendarPlan(
      dates: [a, c, b],
      links: {'b': 'ev-b', 'c': 'ev-c', 'gone': 'ev-gone'},
      sigs: {'b': phoneCalendarSig(b), 'c': 'старая подпись', 'gone': 'x'},
    );
    expect(plan.create.map((d) => d.id), ['a']);
    expect(plan.replace.map((d) => d.id), ['c']);
    expect(plan.remove, {'gone': 'ev-gone'});
  });

  test('готовые даты в календарь телефона не идут', () {
    final auto = autoDates(start: DateTime(2024, 12, 10), birthdays: const {}, myUid: 'me', names: const {});
    final plan = phoneCalendarPlan(dates: auto, links: const {}, sigs: const {});
    expect(plan.create, isEmpty);
  });

  test('подпись меняется от того, что видно в календаре, и не меняется от напоминаний', () {
    final base = _d('a');
    expect(phoneCalendarSig(base.copyWith(reminders: [30])), phoneCalendarSig(base));
    expect(phoneCalendarSig(base.copyWith(title: 'Другое')), isNot(phoneCalendarSig(base)));
    expect(phoneCalendarSig(base.copyWith(exdates: {'2026-11-08'})), isNot(phoneCalendarSig(base)));
    expect(phoneCalendarSig(base.copyWith(rrule: '')), isNot(phoneCalendarSig(base)));
  });

  test('метка в описании находит свою дату', () {
    expect(phoneCalendarNote(_d('abc').copyWith(note: 'Кафе на углу')), 'Кафе на углу\n\ntogetherly:abc');
    expect(phoneCalendarNote(_d('abc')), 'togetherly:abc');
    expect(dateIdFromNote('Кафе\n\ntogetherly:abc'), 'abc');
    expect(dateIdFromNote('чужое событие'), isNull);
  });
}
