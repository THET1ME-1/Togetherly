import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Геопозиция не должна включаться, когда партнёра нет.
///
/// Правило проверяется по исходнику, а не прогоном сервиса: `startSharing`
/// поднимает поток `geolocator` и пишет в RTDB — без устройства это не
/// запускается. Зато сторож ловит ровно тот класс поломки, который уже стоил
/// реджекта 2.5.4: кто-нибудь снимет условие, приложение снова начнёт брать
/// координаты у одиночек, и App Review опять не найдёт функции под режим
/// `location`.
void main() {
  final src = File('lib/services/live_location_service.dart').readAsStringSync();

  test('startSharing выходит на пустом partnerUid', () {
    final body = _between(src, 'Future<void> startSharing(', 'Future<void> stopSharing(');
    expect(body.contains('partnerUid.isEmpty'), isTrue,
        reason: 'без проверки партнёра шеринг стартует у одиночек');
    final at = body.indexOf('partnerUid.isEmpty');
    final fgs = body.indexOf('_canStartFgs');
    expect(at < fgs, isTrue,
        reason: 'проверка партнёра обязана стоять ДО подъёма потока');
  });

  test('resumeIfEnabled гасит остаток, когда партнёра не стало', () {
    final body = _between(src, 'Future<void> resumeIfEnabled(', 'void _watchLifecycle(');
    expect(body.contains('partnerUid.isEmpty'), isTrue);
    expect(body.contains('stopSharing(removePoint: true)'), isTrue,
        reason: 'после распада пары точка обязана исчезнуть из RTDB');
  });

  test('читать точку партнёра без него по-прежнему нельзя', () {
    final body = _between(src, 'Stream<LivePoint?> watchPartner(', 'Stream<LivePoint?> watchSelf(');
    expect(body.contains('partnerUid.isEmpty'), isTrue);
  });
}

String _between(String src, String from, String to) {
  final a = src.indexOf(from);
  final b = src.indexOf(to, a);
  expect(a >= 0 && b > a, isTrue, reason: 'не найден участок $from');
  return src.substring(a, b);
}
