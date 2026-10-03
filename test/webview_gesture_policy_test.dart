import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// На iOS 26 распознаватель жестов Flutter с политикой eager застревает после
/// любого модального окна — рекламы перед комнатой просмотра, — и браузер
/// комнаты не получает ни одного касания: замер room-no-touch 36% заходов с
/// iPhone после рекламы, обращения 226 и 229 (03.10.2026). Лечит политика
/// DoNotBlockGesture (Flutter 3.47+) в копии плагина в third_party.
void main() {
  test('браузер комнаты зарегистрирован с DoNotBlockGesture', () {
    final src = File('third_party/flutter_inappwebview_ios/ios/flutter_inappwebview_ios/'
            'Sources/flutter_inappwebview_ios/InAppWebViewFlutterPlugin.swift')
        .readAsStringSync();
    expect(src, contains('FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture'));
  });

  test('копия плагина подключена вместо пакета из pub.dev', () {
    final lock = File('pubspec.lock').readAsStringSync();
    expect(lock, contains('path: "third_party/flutter_inappwebview_ios"'));
  });

  test('CI собирает на Flutter с этой политикой', () {
    for (final f in Directory('.github/workflows').listSync()) {
      if (f is! File || !f.path.endsWith('.yml')) continue;
      for (final m in RegExp(r'flutter-version: (\d+)\.(\d+)').allMatches(f.readAsStringSync())) {
        final major = int.parse(m.group(1)!), minor = int.parse(m.group(2)!);
        expect(major > 3 || (major == 3 && minor >= 47), isTrue, reason: '${f.path}: ${m.group(0)}');
      }
    }
  });
}
