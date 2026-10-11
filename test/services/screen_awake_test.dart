import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/screen_awake.dart';

/// Экран гас посреди фильма (жалоба 12.10.2026, Xiaomi: «видео идёт, а экран
/// тухнет как при бездействии»). Приложение ни в одном месте не просило
/// систему держать экран: ни плагин `video_player`, ни встроенный браузер
/// сами этого не делают.
void main() {
  late List<bool> calls;

  setUp(() {
    calls = [];
    ScreenAwake.debugReset((on) async => calls.add(on));
  });

  test('первый, кому нужен экран, включает удержание', () {
    final player = Object();
    ScreenAwake.hold(player);
    expect(calls, [true]);
    expect(ScreenAwake.held, isTrue);
  });

  test('повторная просьба того же экрана систему не дёргает', () {
    final player = Object();
    ScreenAwake.hold(player);
    ScreenAwake.hold(player);
    expect(calls, [true]);
  });

  test('удержание снимается, только когда отпустили все', () {
    // Плеер ролика открыт поверх комнаты: закрыли плеер — комната ещё на
    // экране, и гаснуть ему рано.
    final room = Object(), player = Object();
    ScreenAwake.hold(room);
    ScreenAwake.hold(player);
    ScreenAwake.release(player);
    expect(calls, [true]);
    expect(ScreenAwake.held, isTrue);

    ScreenAwake.release(room);
    expect(calls, [true, false]);
    expect(ScreenAwake.held, isFalse);
  });

  test('отпустить то, что не держали, — не ошибка', () {
    ScreenAwake.release(Object());
    expect(calls, isEmpty);
  });

  test('sync держит экран, пока видео играет, и отпускает на паузе', () {
    final player = Object();
    ScreenAwake.sync(player, playing: true);
    ScreenAwake.sync(player, playing: true);
    ScreenAwake.sync(player, playing: false);
    ScreenAwake.sync(player, playing: false);
    expect(calls, [true, false]);
  });

  test('сбой плагина не роняет плеер', () {
    ScreenAwake.debugReset((on) => Future<void>.error(StateError('нет окна')));
    expect(() => ScreenAwake.hold(Object()), returnsNormally);
  });

  test('каждый экран с видео держит экран включённым', () {
    // Новый видеоэкран без этой строки погаснет посреди ролика: система
    // считает человека бездействующим, пока он просто смотрит.
    String read(String path) => File(path).readAsStringSync();
    expect(read('lib/screens/together/watch_room_screen.dart'),
        allOf(contains('ScreenAwake.hold(this)'), contains('ScreenAwake.release(this)')),
        reason: 'комната просмотра и ленты');
    for (final path in [
      'lib/screens/together/watch_player_screen.dart',
      'lib/screens/memory_lane/media_widgets.dart',
    ]) {
      final source = read(path);
      expect(source, contains('ScreenAwake.sync(this, playing:'), reason: path);
      expect(source, contains('ScreenAwake.release(this)'), reason: path);
    }
    // В файле плееров ленты их два: свой ролик и встроенный YouTube.
    final players = read('lib/screens/memory_lane/media_widgets.dart');
    expect('ScreenAwake.sync(this,'.allMatches(players).length +
            'ScreenAwake.sync(\n'.allMatches(players).length,
        2);
    expect('ScreenAwake.release(this)'.allMatches(players).length, 2);
  });

  test('имя канала одно в Dart, Kotlin и Swift', () {
    // Разъедутся — вызов молча уйдёт в никуда: отказ натива служба глотает,
    // чтобы не ронять плеер, и экран снова начнёт гаснуть без единой ошибки.
    String read(String path) => File(path).readAsStringSync();
    const name = 'love_app/screen_awake';
    expect(read('lib/services/screen_awake.dart'), contains("'$name'"));
    final kotlin =
        read('android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt');
    expect(kotlin, contains('"$name"'));
    expect(kotlin, contains('FLAG_KEEP_SCREEN_ON'));
    expect(kotlin, contains('call.argument<Boolean>("on")'));
    final swift = read('ios/Runner/AppDelegate.swift');
    expect(swift, contains('"$name"'));
    expect(swift, contains('isIdleTimerDisabled = on'));
    expect(swift, contains('setupScreenAwakeChannel(engineBridge.pluginRegistry)'));
  });
}
