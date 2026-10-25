// TOG-36: пуш, пришедший при открытом приложении, доходит до Dart.
//
// Нативная часть (FcmService.onMessageReceived на Android, willPresent на
// iPhone) шлёт в канал love_app/push_arrived вид пуша. Здесь её изображает
// сообщение, поданное в канал напрямую.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/push_arrivals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> nativeSays(String method, Object? arguments) async {
    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      PushArrivals.channelName,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  test('пуш о сообщении доходит до тех, кто ждёт чат, и только до них', () async {
    final chat = <int>[];
    final mood = <int>[];
    final a = PushArrivals.instance.of('chat').listen((_) => chat.add(1));
    final b = PushArrivals.instance.of('mood').listen((_) => mood.add(1));

    await nativeSays('arrived', 'chat');
    await nativeSays('arrived', 'chat');
    await nativeSays('arrived', 'memory');
    await Future<void>.delayed(Duration.zero);

    expect(chat, hasLength(2));
    expect(mood, isEmpty);
    await a.cancel();
    await b.cancel();
  });

  test('чужие и пустые сообщения канала ничего не роняют', () async {
    final chat = <int>[];
    final sub = PushArrivals.instance.of('chat').listen((_) => chat.add(1));
    await nativeSays('arrived', null);
    await nativeSays('arrived', '');
    await nativeSays('opened', 'chat');
    await Future<void>.delayed(Duration.zero);
    expect(chat, isEmpty);
    await sub.cancel();
  });
}
