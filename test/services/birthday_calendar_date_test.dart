// День рождения уезжал на сутки назад у тех, кто родился ночью.
//
// Письмо 23 августа 2026: «указала 2 октября 2005 и 02:45, показывает
// 1 октября 2005 и 23:45. Сколько раз исправляла, оно обратно». Разница ровно
// в её поясе (UTC+3): клиент клал ДР МОМЕНТОМ ВРЕМЕНИ в UTC
// (`PairTime.write` → `2005-10-01T23:45:00.000Z`), а читал календарный день
// прямо из строки. Полночь между вводом и хранением — и число другое.
//
// У дня рождения нет ни часа, ни пояса: 2 октября остаётся 2 октября везде.
// Поэтому на сервер он уходит строкой `ГГГГ-ММ-ДД`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/pb_data_service.dart';
import 'package:love_app/utils/date_only.dart';

void main() {
  test('день рождения уходит календарной датой, без часа и пояса', () {
    final row = PbDataService.userProfileRow({
      'birthDate': DateTime(2005, 10, 2, 2, 45),
    });

    expect(row['birth_date'], '2005-10-02');
  });

  test('ночной час не уносит день на вчера', () {
    for (final moment in [
      DateTime(2005, 10, 2, 0, 5),
      DateTime(2005, 10, 2, 2, 45),
      DateTime(2005, 10, 2, 23, 55),
    ]) {
      final row = PbDataService.userProfileRow({'birthDate': moment});
      final back = DateOnly.parse(row['birth_date'])!;

      expect([back.year, back.month, back.day], [2005, 10, 2],
          reason: 'момент $moment не должен менять число');
    }
  });

  test('пустая дата стирает поле, а не пропадает молча', () {
    final row = PbDataService.userProfileRow({'birthDate': null});

    expect(row.containsKey('birth_date'), isTrue);
    expect(row['birth_date'], isNull);
  });

  test('остальные поля профиля собираются как прежде', () {
    final row = PbDataService.userProfileRow({
      'displayName': 'Ангелина',
      'gender': 'female',
    });

    expect(row['display_name'], 'Ангелина');
    expect(row['gender'], 'female');
    expect(row.containsKey('birth_date'), isFalse);
  });

  test('у дня рождения не спрашивают час', () {
    // Час всё равно не уезжает на сервер: спрашивать его — обещать то, чего
    // приложение не сделает. Ангелина ввела 02:45 и решила, что её правку
    // отменяют.
    final screen = File('lib/screens/profile_screen.dart').readAsStringSync();
    final start = screen.indexOf('Future<void> _showBirthdayPicker(');
    expect(start, greaterThan(0), reason: 'пикер дня рождения на месте');
    final body = screen.substring(start, screen.indexOf(');', start));

    expect(body.contains('withTime: false'), isTrue,
        reason: 'вкладка времени у дня рождения выключена');
  });
}
