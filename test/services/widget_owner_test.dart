// Виджеты держат данные пары в хранилище УСТРОЙСТВА, а не аккаунта.
//
// Жалоба 18.08.2026: поставил виджеты на одном аккаунте, вышел, вошёл в другой —
// на столе по-прежнему прошлая пара. Проверка владельца была всего одна, в
// `main()`, то есть срабатывала только на холодном старте: смена аккаунта в
// живом приложении её не задевала вовсе, а выход не стирал ничего.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_owner.dart';

void main() {
  test('вышли из аккаунта — стираем, владельца забываем', () {
    expect(widgetOwnerAction(previous: 'u1', current: ''),
        WidgetOwnerAction.wipeAndForget);
    expect(widgetOwnerAction(previous: null, current: ''),
        WidgetOwnerAction.wipeAndForget);
  });

  test('вошёл другой человек — стираем и запоминаем нового', () {
    expect(widgetOwnerAction(previous: 'u1', current: 'u2'),
        WidgetOwnerAction.wipeAndRemember);
  });

  test('тот же человек — не трогаем ничего', () {
    expect(widgetOwnerAction(previous: 'u1', current: 'u1'),
        WidgetOwnerAction.none,
        reason: 'обновление токена шлёт то же событие по нескольку раз за запуск');
  });

  test('владельца ещё не записывали — запоминаем, но не стираем', () {
    expect(widgetOwnerAction(previous: null, current: 'u1'),
        WidgetOwnerAction.remember,
        reason: 'иначе первый же запуск после обновления сносит виджеты с экрана');
    expect(widgetOwnerAction(previous: '', current: 'u1'),
        WidgetOwnerAction.remember);
  });
}
