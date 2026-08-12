import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож зависшего показа рекламы.
///
/// Показ rewarded держится на колбэках SDK: награда, закрытие, отказ. Если ни
/// один не приходит — а на iOS так и бывает, когда SDK Яндекса не находит
/// контроллер и молчит вовсе, — ожидание не кончается никогда. Экран, который
/// его ждёт, замирает: совместный просмотр так запирался у обоих партнёров
/// сразу. Поэтому каждое ожидание колбэка обязано иметь предохранитель.
void main() {
  test('ожидание колбэков рекламы всегда ограничено таймаутом', () {
    final source =
        File('lib/services/rewarded_ad_service.dart').readAsStringSync();

    // Ждём завершения Completer'ов показа — каждое такое ожидание должно
    // заканчиваться само, даже когда SDK не отвечает.
    final awaits = RegExp(r'await\s+(dismissed|completer)\.future([\s\S]{0,80})')
        .allMatches(source);

    expect(
      awaits,
      isNotEmpty,
      reason: 'Ожидания показа рекламы не найдены — тест устарел, поправьте его '
          'вместе с сервисом',
    );

    final offenders = <String>[];
    for (final match in awaits) {
      final tail = match.group(2) ?? '';
      if (tail.contains('.timeout(')) continue;
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      offenders.add('rewarded_ad_service.dart:$line');
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Без таймаута молчание рекламной SDK вешает экран навсегда: '
          '${offenders.join(', ')}',
    );
  });
}
