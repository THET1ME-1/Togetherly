import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Окно «Разрешить уведомления?» вылезало посреди входа через Google
/// (09.11.2026, владелец: «зачем в этот момент именно»). Вход открывает
/// страницу Google поверх приложения, приложение уходит в фон, а на уходе в
/// фон напоминание маскота ставило себя и заодно просило разрешение. На
/// iPhone то же окно поднимал старт приложения ещё до входа.
///
/// Разрешение спрашивает главный экран, когда ставит напоминания про даты
/// (`rescheduleOnAppStart`), то есть уже после входа. Напоминание маскота
/// только ставится: без разрешения оно просто не покажется.
void main() {
  test('напоминание маскота разрешение не просит', () {
    final src = File('lib/services/mascot_inactivity_notification_service.dart').readAsStringSync();
    expect(src, isNot(contains('requestNotificationPermissionSafely')));
    expect(src, isNot(contains('requestPermissions(')));
  });

  test('главный экран по-прежнему ставит напоминания, которые просят разрешение', () {
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(home, contains('DaysTogetherNotificationService.instance.rescheduleOnAppStart()'));
    final days = File('lib/services/days_together_notification_service.dart').readAsStringSync();
    expect(days, contains('requestNotificationPermissionSafely'));
  });
}
