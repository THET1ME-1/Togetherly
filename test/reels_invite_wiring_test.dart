import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Зов в совместную ленту едет через четыре места: сервер кладёт поля в пуш,
/// Kotlin и Swift передают их каналом, Dart разбирает. Разъедется имя канала
/// или поля — пуш придёт, а касание по нему ничего не откроет, молча.
void main() {
  final dart = File('lib/services/reels/reels_invite.dart').readAsStringSync();
  final kotlin = File('android/app/src/main/kotlin/com/togetherly/love/ReelsInviteBridge.kt').readAsStringSync();
  final activity = File('android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt').readAsStringSync();
  final fcm = File('android/app/src/main/kotlin/com/togetherly/love/FcmService.kt').readAsStringSync();
  final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  final hook = File('pocketbase/pb_hooks/reels_invite.pb.js').readAsStringSync();

  test('канал один и тот же', () {
    for (final src in [dart, kotlin, swift]) {
      expect(src.contains('love_app/reels_invite'), isTrue);
    }
  });

  test('методы канала совпадают', () {
    for (final m in ['pending', 'opened', 'arrived']) {
      expect(dart.contains("'$m'"), isTrue, reason: 'Dart: $m');
      expect(kotlin.contains('"$m"'), isTrue, reason: 'Kotlin: $m');
      expect(swift.contains('"$m"'), isTrue, reason: 'Swift: $m');
    }
  });

  test('поля пуша, которые шлёт сервер, читают обе платформы', () {
    for (final f in ['feed', 'group', 'name']) {
      expect(hook.contains('$f:'), isTrue, reason: 'сервер: $f');
      expect(kotlin.contains('"$f"'), isTrue, reason: 'Kotlin: $f');
      expect(swift.contains('"$f"'), isTrue, reason: 'Swift: $f');
    }
    expect(hook.contains('"reels"'), isTrue);
  });

  test('в данных пуша нет служебного ключа Firebase from', () {
    expect(RegExp(r'data:\s*\{[^}]*\bfrom:').hasMatch(hook), isFalse,
        reason: 'с ключом from FCM отвечает INVALID_ARGUMENT, и релей стирает живой токен');
  });

  test('Android подключает мост и ловит пуш на переднем плане', () {
    expect(activity.contains('ReelsInviteBridge.attach'), isTrue);
    expect(activity.contains('ReelsInviteBridge.fromIntent(intent, warm = false)'), isTrue);
    expect(activity.contains('ReelsInviteBridge.fromIntent(intent, warm = true)'), isTrue);
    expect(fcm.contains('ReelsInviteBridge.arrived'), isTrue);
  });

  test('iPhone поднимает канал вместе с движком', () {
    expect(swift.contains('setupReelsInviteChannel(engineBridge.pluginRegistry)'), isTrue);
  });
}
