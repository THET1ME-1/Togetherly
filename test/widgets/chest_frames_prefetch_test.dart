import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';

/// `prefetch` обязан завершаться, чем бы ни кончилась загрузка. До 08.10.2026
/// он ждал сам себя: `whenComplete(() => _loading.remove(url))` возвращал ту же
/// загрузку, и `whenComplete` ждал её вечно. Обычный сундук на главной и на
/// экране, которые просят файл сами в момент показа, из-за этого стояли
/// картинкой (разбор на эмуляторе, жалоба с 1.35.0+245).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
  });

  test('prefetch завершается, а не ждёт сам себя', () async {
    // В тестах сеть отвечает 400 — загрузка падает сразу, но ожидание
    // всё равно обязано закончиться.
    await expectLater(
      ChestFrames.prefetch('https://example.invalid/chest_idle.webp').timeout(const Duration(seconds: 20)),
      completes,
    );
  });

  test('повторный prefetch того же адреса тоже завершается', () async {
    const url = 'https://example.invalid/chest_open.webp';
    final a = ChestFrames.prefetch(url), b = ChestFrames.prefetch(url);
    await expectLater(Future.wait([a, b]).timeout(const Duration(seconds: 20)), completes);
  });
}
