import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/cinema_chrome.dart';

// Режим «кино» в комнате просмотра (TOG-43, обращение 488): на Android
// оставались строка состояния и кнопки навигации, по краям лежали поля, а стоя
// ролик шёл узкой полосой, потому что телефон не поворачивался.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('вход прячет панели и кладёт телефон набок', () async {
    await CinemaChrome.enter();
    final mode = calls.firstWhere((c) => c.method == 'SystemChrome.setEnabledSystemUIMode');
    expect(mode.arguments, 'SystemUiMode.immersiveSticky');
    final turn = calls.firstWhere((c) => c.method == 'SystemChrome.setPreferredOrientations');
    expect(turn.arguments, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);
  });

  test('выход возвращает панели и свободный поворот', () async {
    await CinemaChrome.leave();
    final mode = calls.firstWhere((c) => c.method == 'SystemChrome.setEnabledSystemUIMode');
    expect(mode.arguments, 'SystemUiMode.edgeToEdge');
    final turn = calls.firstWhere((c) => c.method == 'SystemChrome.setPreferredOrientations');
    expect(turn.arguments, isEmpty);
  });

  test('страница и приложение называют мост одинаково', () {
    final page = File('pocketbase/pb_public/watch/room/room.js').readAsStringSync();
    final screen = File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
    expect(page, contains("callHandler('watchCinema'"));
    expect(screen, contains("handlerName: 'watchCinema'"));
    expect(page, contains('window.roomExitCinema'));
    expect(screen, contains('roomExitCinema'));
  });

  test('в «кино» страница ложится во весь экран, без отступов SafeArea', () {
    final screen = File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
    expect(screen, contains('left: !_cinema'));
    expect(screen, contains('right: !_cinema'));
    expect(screen, contains('top: !widget.reels && !_cinema'));
  });

  test('уход с экрана возвращает окно, даже если «кино» не выключали', () {
    final screen = File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
    final dispose = screen.substring(screen.indexOf('void dispose() {'));
    expect(dispose.substring(0, dispose.indexOf('\n  }')), contains('CinemaChrome.leave()'));
  });
}
