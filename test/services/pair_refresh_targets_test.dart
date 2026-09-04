// Кого фон обновляет и кто из них пишет общие ключи.
//
// `widgetRefreshDispatcher` брал единственную пару из `love_widget_group_id` —
// ту, что открыта в приложении. Виджет второй связи застывал до переключения:
// человек видел на столе позавчерашнее настроение и не понимал, почему
// «виджеты не обновляются» (задача от 01.09.2026, жалобы людей с двумя парами).
//
// Общие ключи (`my_status` и прочие без пары в имени) остаются одни на всех,
// поэтому писать в них имеет право только открытая пара — иначе связи снова
// начнут затирать друг друга, и мы вернёмся ровно туда, откуда ушли.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/pair_widget_payload.dart';

void main() {
  test('открытая пара идёт первой и пишет общие ключи', () {
    final targets = pairsToRefresh(
      groups: const ['a', 'b', 'c'],
      activeGroupId: 'b',
    );
    expect(targets.first.groupId, 'b');
    expect(targets.first.shared, isTrue);
    expect(targets.where((t) => t.shared), hasLength(1),
        reason: 'иначе связи снова затирают друг друга в общих ключах');
  });

  test('остальные пары обновляются каждая в свои ключи', () {
    final targets = pairsToRefresh(
      groups: const ['a', 'b'],
      activeGroupId: 'a',
    );
    expect(targets.map((t) => t.groupId), ['a', 'b']);
    expect(targets.last.shared, isFalse);
  });

  test('открытая пара обновляется, даже если списка групп нет', () {
    final targets = pairsToRefresh(groups: const [], activeGroupId: 'a');
    expect(targets.map((t) => t.groupId), ['a']);
    expect(targets.single.shared, isTrue);
  });

  test('повторы и пустые строки отбрасываются', () {
    final targets = pairsToRefresh(
      groups: const ['a', '', 'a', 'b'],
      activeGroupId: 'a',
    );
    expect(targets.map((t) => t.groupId), ['a', 'b']);
  });

  test('без открытой пары общие ключи не трогает никто', () {
    final targets = pairsToRefresh(groups: const ['a', 'b'], activeGroupId: '');
    expect(targets.map((t) => t.groupId), ['a', 'b']);
    expect(targets.any((t) => t.shared), isFalse);
  });

  // Фоновое пробуждение короткое, а пар у человека бывает и десяток: пройти
  // все — значит не успеть ни одной. Открытая всё равно первая, поэтому
  // обрезаем хвост, а не голову.
  test('за один проход берём не больше пяти пар', () {
    final targets = pairsToRefresh(
      groups: const ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
      activeGroupId: 'f',
    );
    expect(targets, hasLength(5));
    expect(targets.first.groupId, 'f');
  });
}
