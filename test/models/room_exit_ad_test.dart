import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/room_exit_ad.dart';

/// Ролик перед комнатой ломал касания на iPhone (19.10.2026: 45% заходов без
/// касания после рекламы против 9% без неё), поэтому реклама переехала на
/// выход из комнаты.
void main() {
  const resumed = AppLifecycleState.resumed;

  test('после комнаты ролик показываем', () {
    expect(roomExitAdDue(plus: false, reels: false, lifecycle: resumed), isTrue);
  });

  test('с Плюсом ролика нет', () {
    expect(roomExitAdDue(plus: true, reels: false, lifecycle: resumed), isFalse);
  });

  test('после лент ролика нет', () {
    expect(roomExitAdDue(plus: false, reels: true, lifecycle: resumed), isFalse);
  });

  test('приложение не на экране — ролик не показываем', () {
    for (final lifecycle in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
      null,
    ]) {
      expect(roomExitAdDue(plus: false, reels: false, lifecycle: lifecycle), isFalse, reason: '$lifecycle');
    }
  });
}
