import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Реклама совместного просмотра идёт после выхода из комнаты, а не перед
/// входом (19.10.2026). Экран комнаты в тесте не поднять, поэтому связку
/// сверяем по исходнику входа.
void main() {
  final launcher = File('lib/screens/together/together_launcher.dart').readAsStringSync();

  test('перед комнатой рекламы нет', () {
    expect(launcher, isNot(contains('RewardedAdService')));
    expect(launcher, isNot(contains('showModalBottomSheet')));
  });

  test('карточка «Смотрим» не обещает рекламу перед комнатой', () {
    final home = File('lib/screens/together/watch_home_screen.dart').readAsStringSync();
    expect(home, isNot(contains('watchAfterShortAd')));
  });

  test('ролик ждёт выход и из комнаты, и из плеера ролика', () {
    expect('await navigator.push('.allMatches(launcher).length, 2);
    expect('await _afterRoom('.allMatches(launcher).length, 2);
  });

  test('ролик из своего блока комнаты', () {
    expect(launcher, contains('InterstitialAdService(room: true)'));
  });

  test('ролик встаёт, когда экран комнаты ушёл целиком', () {
    final body = launcher.substring(launcher.indexOf('static Future<void> _afterRoom('));
    final completed = body.indexOf('await route.completed');
    expect(completed, isNonNegative);
    expect(completed, lessThan(body.indexOf('_exitAd.show(')));
  });
}
