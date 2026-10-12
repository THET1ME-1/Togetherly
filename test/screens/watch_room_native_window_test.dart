import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Нативное окно комнаты на iPhone (12.10.2026) держится на связке из пяти
/// мест: флаг с сервера, правило во входе, экран, метки в адресе и страница.
/// Разъедется любое — и окно молча не откроется либо откроется без шапки,
/// выхода или замера. Экран со встроенным браузером в тесте не поднять,
/// поэтому связку сверяем по исходникам.
void main() {
  String read(String path) => File(path).readAsStringSync();

  final screen = read('lib/screens/together/watch_room_screen.dart');
  final launcher = read('lib/screens/together/together_launcher.dart');
  final data = read('lib/services/pb_data_service.dart');
  final page = read('pocketbase/pb_public/watch/room/room.js');
  final css = read('pocketbase/pb_public/watch/room/room.css');

  test('долю с сервера принимает каждое чтение конфига', () {
    // Конфиг читают несколько мест, и первым до сервера доходит любое из
    // них. Пропустит одно — у части людей доля останется прошлой.
    final wallet = "WalletTeaser.ingest(res.items.first.data['wallet']);".allMatches(data).length;
    final room = "RoomWindowFlag.ingest(res.items.first.data['room_native_ios']);".allMatches(data).length;
    expect(wallet, greaterThan(0));
    expect(room, wallet);
    expect(read('lib/screens/home_screen.dart'), contains('RoomWindowFlag.restore()'));
  });

  test('вход решает правилом и передаёт экрану окно и сборку', () {
    expect(launcher, contains('roomOpensNatively('));
    expect(launcher, contains('share: RoomWindowFlag.share'));
    expect(launcher, contains('nativeWindow: nativeWindow'));
    expect(launcher, contains('build: build'));
  });

  test('окно открывается поверх экрана, а не вместо него', () {
    // FULL_SCREEN снимает экран Flutter с показа: приложение считает себя
    // свёрнутым, гасит отрисовку и присутствие, звонок в комнате рвётся.
    expect(screen, contains('presentationStyle: ModalPresentationStyle.OVER_FULL_SCREEN'));
    expect(screen, isNot(contains('ModalPresentationStyle.FULL_SCREEN')));
  });

  test('панели браузера спрятаны: шапку рисует страница', () {
    for (final line in ['hideToolbarTop: true', 'hideUrlBar: true', 'hideProgressBar: true', 'hideCloseButton: true']) {
      expect(screen, contains(line), reason: line);
    }
  });

  test('мосты страницы одни на оба окна', () {
    // Две копии разъехались бы на первой же новой кнопке страницы.
    expect(screen, contains('onWebViewCreated: _wire,'));
    expect(screen, contains('onCreated: _wire,'));
    expect("handlerName: 'watchBack'".allMatches(screen).length, 1);
    expect("handlerName: 'watchVoice'".allMatches(screen).length, 1);
  });

  test('окно не открылось — комната встаёт встроенным браузером', () {
    expect(screen, contains('setState(() => _native = false)'));
  });

  test('выход закрывает окно, а закрытое системой окно уводит из комнаты', () {
    expect(screen, contains('if (mounted && _allowLeave()) unawaited(_leave());'));
    expect(screen, contains('onClosed: _onWindowClosed'));
    // Маршрут под окном не должен остаться пустым экраном.
    final closed = screen.substring(screen.indexOf('void _onWindowClosed()'));
    expect(closed.substring(0, closed.indexOf('\n  }')), contains('_dropRoute()'));
    // И окно не переживает свой экран.
    final dispose = screen.substring(screen.indexOf('void dispose()'));
    expect(dispose.substring(0, dispose.indexOf('super.dispose()')), contains('_closeWindow()'));
  });

  test('сообщения под нативным окном показывает страница', () {
    // Плашку и снекбар Flutter под окном не видно: «нажмите ещё раз, чтобы
    // выйти» уходило бы в никуда, и человек не мог бы выйти из комнаты.
    expect(screen, contains('window.roomNote && window.roomNote('));
    expect(page, contains('window.roomNote = '));
  });

  test('страница узнаёт окно и сборку по тем же меткам, что шлёт приложение', () {
    final service = read('lib/services/watch_room_service.dart');
    expect(service, contains("query['nb'] = '1'"));
    expect(service, contains("query['b'] = '\$build'"));
    expect(page, contains(r'/[?&]nb=1\b/'));
    expect(page, contains(r'/[?&]b=(\d{1,6})\b/'));
    expect(page, contains("classList.add('native-window')"));
    expect(css, contains('.native-window .room-body'));
  });

  test('отступы под вырез экрана приложение сообщает и нативному окну', () {
    expect(screen, contains('if (widget.reels || _native)'));
    expect(css, contains('var(--app-top, 0px)'));
  });
}
