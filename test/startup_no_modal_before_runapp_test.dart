import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож белого экрана на iOS.
///
/// Пока `runApp` не позвали, окна у приложения нет — есть только launch-заставка.
/// Любой вызов, который в этот момент открывает системное окно и ждёт ответа
/// (разрешение на уведомления, форма согласия рекламы, запрос трекинга),
/// показать это окно не может: iOS не доставляет его неактивной сцене. Future
/// не завершается, `main()` стоит, человек смотрит на белый экран и удаляет
/// приложение. Ровно так уже ломался ATT-попап в июле.
///
/// Правило простое: всё модальное живёт после первого кадра
/// (`addPostFrameCallback` в `_LoveAppState`), а до `runApp` остаётся только
/// работа с диском и памятью.
void main() {
  test('до runApp никто не открывает системных окон', () {
    final source = File('lib/main.dart').readAsStringSync();

    final mainStart = source.indexOf('void main() async {');
    expect(mainStart, isNot(-1), reason: 'main() в lib/main.dart не найден');

    final runAppAt = source.indexOf('runApp(', mainStart);
    expect(runAppAt, isNot(-1), reason: 'вызов runApp() не найден');

    final beforeFirstFrame = source.substring(mainStart, runAppAt);

    // Каждый пункт — вызов, который на iOS показывает системное окно и ждёт,
    // пока человек ответит.
    const modalCalls = <String, String>{
      'MascotInactivityNotificationService.instance.init':
          'запрашивает разрешение на уведомления',
      '_initConsentAndAds(': 'показывает форму согласия UMP',
      'requestPermissions(': 'запрашивает разрешение',
      'requestTrackingAuthorization': 'показывает окно ATT',
      'Geolocator.requestPermission': 'запрашивает геолокацию',
      'ensurePermission(': 'запрашивает разрешение',
    };

    final offenders = <String>[];
    for (final entry in modalCalls.entries) {
      final at = beforeFirstFrame.indexOf(entry.key);
      if (at == -1) continue;
      final line =
          '\n'.allMatches(source.substring(0, mainStart + at)).length + 1;
      offenders.add('main.dart:$line — ${entry.key} ${entry.value}');
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Эти вызовы держат старт до первого кадра и дают белый экран:\n'
          '${offenders.join('\n')}',
    );
  });
}
