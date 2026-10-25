import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/ad_cover.dart';

/// TOG-37: на iPhone плагин Яндекса показывает ролик прозрачным контроллером
/// `.overCurrentContext` поверх Flutter, и приложение не узнаёт, что его
/// накрыли: жизненный цикл стоит на `resumed`. Событие «закрыто» теряется,
/// и экран сундука ждал до 30 минут. Конец ролика видно по стопке
/// контроллеров над Flutter: правило здесь, натив только описывает стопку.
void main() {
  AdCoverSnapshot snap(int depth, {bool pluginTop = false, bool topEmpty = true}) =>
      AdCoverSnapshot(depth: depth, pluginTop: pluginTop, topEmpty: topEmpty);

  test('пустой контроллер плагина до показа ролика — ещё не реклама', () {
    final t = AdCoverTracker()
      ..onSnapshot(snap(0))
      ..onSnapshot(snap(1, pluginTop: true));
    expect(t.sawAd, isFalse);
    expect(t.closed, isFalse);
  });

  test('ролик SDK поверх контроллера плагина — реклама на экране', () {
    final t = AdCoverTracker()
      ..onSnapshot(snap(1, pluginTop: true))
      ..onSnapshot(snap(2));
    expect(t.sawAd, isTrue);
    expect(t.closed, isFalse);
  });

  test('ролик ушёл, а пустой слой плагина остался — закрыто, слой лишний', () {
    final t = AdCoverTracker()
      ..onSnapshot(snap(2))
      ..onSnapshot(snap(1, pluginTop: true));
    expect(t.closed, isTrue);
    expect(t.leftover, isTrue, reason: 'прозрачный слой плагина держит касания');
  });

  test('ушло всё, что было поверх Flutter, — закрыто без лишнего слоя', () {
    final t = AdCoverTracker()
      ..onSnapshot(snap(2))
      ..onSnapshot(snap(0));
    expect(t.closed, isTrue);
    expect(t.leftover, isFalse);
  });

  test('ролик внутри контроллера плагина, без своего контроллера, тоже виден', () {
    final t = AdCoverTracker()
      ..onSnapshot(snap(1, pluginTop: true, topEmpty: false))
      ..onSnapshot(snap(1, pluginTop: true));
    expect(t.sawAd, isTrue);
    expect(t.closed, isTrue);
    expect(t.leftover, isTrue);
  });

  test('без показа закрытия нет: пустая стопка с самого начала', () {
    final t = AdCoverTracker()
      ..onSnapshot(snap(0))
      ..onSnapshot(snap(0));
    expect(t.closed, isFalse);
    expect(t.sawAd, isFalse);
  });

  test('чужой контроллер поверх Flutter рекламой не считается', () {
    // Лист «Поделиться» или системный выбор фото: не плагин и без ролика внутри.
    final t = AdCoverTracker()..onSnapshot(snap(1));
    expect(t.sawAd, isFalse);
  });

  test('разбор ответа натива: кривой ответ — пустая стопка', () {
    expect(AdCoverSnapshot.fromMap({'depth': 2, 'pluginTop': true, 'topEmpty': false}).depth, 2);
    final odd = AdCoverSnapshot.fromMap('мусор');
    expect(odd.depth, 0);
    expect(odd.pluginTop, isFalse);
    expect(odd.topEmpty, isTrue);
  });
}
