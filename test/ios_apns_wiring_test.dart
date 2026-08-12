import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож пушей на iPhone.
///
/// Уведомления рисует само приложение по своему сокету, а iOS выгружает процесс
/// вместе с сокетом — с закрытым приложением человек не узнаёт ни о сообщении,
/// ни о «скучаю». Работает это только через APNs, и держится на трёх звеньях:
/// нативная регистрация устройства, канал токена в Dart и запись токена в
/// профиль, откуда его берёт серверный хук `push_apns.pb.js`.
///
/// Любое пропавшее звено ломает пуши молча: приложение работает, просто уведомы
/// не приходят. Поэтому проверяем, что все три на месте.
void main() {
  test('нативная сторона просит токен устройства и отдаёт его в канал', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('registerForRemoteNotifications'),
        reason: 'без регистрации Apple не выдаст токен');
    expect(source, contains('didRegisterForRemoteNotificationsWithDeviceToken'),
        reason: 'токен приходит именно в этот метод');
    expect(source, contains("love_app/apns"),
        reason: 'канал токена должен совпадать с ApnsService');
  });

  test('Dart кладёт токен в профиль, откуда его читает сервер', () {
    final source = File('lib/services/apns_service.dart').readAsStringSync();

    expect(source, contains("MethodChannel('love_app/apns')"));
    expect(source, contains('apns_token'),
        reason: 'поле профиля читает серверный хук');
    expect(source, contains('apns_sandbox'),
        reason: 'сборки из Xcode ходят через песочницу Apple');
  });

  test('сервис поднимается на старте, за первым кадром', () {
    final source = File('lib/main.dart').readAsStringSync();
    final deferredAt = source.indexOf('_initDeferredStartup');
    expect(deferredAt, isNot(-1));
    expect(source, contains('ApnsService.instance.start()'),
        reason: 'без вызова токен никто не запросит');
  });

  test('серверный хук не шлёт пуш тому, кто на связи', () {
    final source =
        File('pocketbase/pb_hooks/push_apns.pb.js').readAsStringSync();

    expect(source, contains('user_presence'),
        reason: 'иначе баннер придёт дважды: от Apple и от живого сокета');
    expect(source, contains('apns_token'));
    expect(source, contains('chat_messages'));
    expect(source, contains('miss_you'));
  });
}
