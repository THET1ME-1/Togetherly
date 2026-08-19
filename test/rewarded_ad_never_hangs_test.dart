import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож зависшего показа рекламы.
///
/// Показ rewarded держится на колбэках SDK: награда, закрытие, отказ. Если ни
/// один не приходит — а на iOS так и бывает, когда SDK Яндекса не находит
/// контроллер и молчит вовсе, — ожидание не кончается никогда. Экран, который
/// его ждёт, замирает: совместный просмотр так запирался у обоих партнёров
/// сразу. Поэтому каждое ожидание колбэка обязано иметь предохранитель.
///
/// Предохранитель — не единственное условие. Пока он один стоял на две минуты,
/// человек честно ждал эти две минуты: медиана ожидания по журналу — ровно 120
/// секунд, и ни одного случая «закрыл рекламу сам». Поэтому ожидание обязано
/// заканчиваться ещё и по возврату приложения на передний план.
void main() {
  test('ожидание колбэков рекламы всегда ограничено таймаутом', () {
    final source =
        File('lib/services/rewarded_ad_service.dart').readAsStringSync();

    // Ожидание закрытия живёт в одном месте — `_awaitAdClosed`, и на нём
    // стоит предохранитель.
    expect(
      RegExp(r'Future<void> _awaitAdClosed\(').hasMatch(source),
      isTrue,
      reason: 'Ожидание показа рекламы не найдено — тест устарел, поправьте его '
          'вместе с сервисом',
    );
    expect(
      RegExp(r'\.timeout\(kAdShowGuard').hasMatch(source),
      isTrue,
      reason: 'Без предохранителя молчание рекламной SDK вешает экран навсегда',
    );

    // Голых ожиданий колбэка мимо этого места быть не должно.
    final offenders = <String>[];
    for (final match
        in RegExp(r'await\s+(dismissed|completer)\.future([\s\S]{0,80})')
            .allMatches(source)) {
      if ((match.group(2) ?? '').contains('.timeout(')) continue;
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      offenders.add('rewarded_ad_service.dart:$line');
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Ожидание в обход предохранителя: ${offenders.join(', ')}',
    );
  });

  test('показ заканчивается и по возврату приложения, а не только по времени', () {
    final source =
        File('lib/services/rewarded_ad_service.dart').readAsStringSync();
    expect(source.contains('AdShowWatch'), isTrue,
        reason: 'ожидание не смотрит на возврат приложения — человек будет '
            'ждать полный предохранитель, как было с двумя минутами');
    expect(source.contains('kAdShowGuard'), isTrue,
        reason: 'предохранитель задан числом на месте, а не общей константой');
  });
}
