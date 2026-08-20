import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Голос в комнате: кнопка на странице, связь в приложении.
///
/// Полоса `WatchVoiceBar` стояла в `bottomNavigationBar` экрана комнаты и
/// приносила две беды сразу. Первая видна на любом снимке: светлая панель
/// Material под тёмной страницей комнаты, чужой радиус и чужой шрифт. Вторая
/// молчит: полоса выезжала через секунду после открытия и отрезала у WebView
/// 84 точки, а страница к тому времени уже прибила себе высоту — поле
/// сообщения и «Отправить» оставались за нижним краем («опять ничего не
/// нажимается» с двух айфонов 20.08.2026).
///
/// Теперь кнопка живёт в шапке самой комнаты, а приложение получает нажатия
/// мостом и возвращает состояние. Разъезд имён действий между Dart и
/// страницей ничем себя не выдаёт — кнопка просто перестаёт работать, — так
/// что сверяем их здесь.
void main() {
  final screen = File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
  final page = File('pocketbase/pb_public/watch/room/room.js').readAsStringSync();

  test('экран комнаты не отрезает высоту у WebView', () {
    expect(screen.contains('bottomNavigationBar'), isFalse,
        reason: 'панель под WebView меняет его размер уже после загрузки');
  });

  test('приложение слушает мост страницы', () {
    expect(screen.contains("handlerName: 'watchVoice'"), isTrue);
    expect(screen.contains('watchVoiceState'), isTrue,
        reason: 'без ответа страница не узнает, что связь поднялась');
  });

  test('страница и приложение зовут действия одинаково', () {
    for (final action in ['call', 'hangup', 'mic']) {
      expect(page.contains("say('$action')"), isTrue,
          reason: 'страница обязана слать действие $action');
      expect(screen.contains("'$action'"), isTrue,
          reason: 'приложение обязано разбирать действие $action');
    }
  });

  test('состояния звонка названы одинаково с обеих сторон', () {
    for (final state in ['connecting', 'live', 'failed']) {
      expect(page.contains("'$state'"), isTrue, reason: 'страница знает $state');
      expect(screen.contains("'$state'"), isTrue, reason: 'приложение шлёт $state');
    }
  });
}
