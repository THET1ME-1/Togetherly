import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Задание дня закрывает только запись, которую сделал человек. Копии,
/// которые приложение само кладёт в ленту с виджета (сообщение, фото,
/// песня), его не закрывают: утреннее сообщение в виджете отмечало
/// «Вспомни любимый момент», хотя на задание никто не отвечал
/// (обращение 236, 05.10.2026).
void main() {
  test('автокопии с виджета не засчитываются в задание', () {
    final src = File('lib/services/widget_service.dart').readAsStringSync();
    final calls = RegExp(r'MemoryRepository\(\)\.add\(([\s\S]*?)\);').allMatches(src).toList();
    expect(calls.length, greaterThanOrEqualTo(3), reason: 'сообщение, фото и песня');
    for (final c in calls) {
      expect(c.group(1), contains('countsForDailyTask: false'),
          reason: 'копия с виджета без флага снова закроет задание дня');
    }
  });

  test('репозиторий не зовёт задание для автокопий', () {
    final src = File('lib/services/memory_repository.dart').readAsStringSync();
    expect(src, contains('bool countsForDailyTask = true'));
    expect(RegExp(r'if \(countsForDailyTask[^)]*\)\s*\{\s*unawaited\(DailyTaskService').hasMatch(src), isTrue,
        reason: 'onMemoryCreated должен стоять под проверкой флага');
  });
}
