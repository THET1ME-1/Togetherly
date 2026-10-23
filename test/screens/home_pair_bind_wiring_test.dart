import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TOG-24: на каждом запуске виджет таймера на рабочем столе стирался. Главная
/// при появлении пары сперва отвязывала таймеры (`unbindFromGroup` переходит на
/// соло и пишет в виджет соло-таймер, а без него пустоту) и только потом
/// привязывала их к паре. Виджет возвращался через пару секунд, а если
/// приложение закрывали раньше, оставался пустым. `bindToGroup` сам сбрасывает
/// прежнюю пару, шаг через соло не нужен.
void main() {
  test('переход к паре не проходит через соло-таймеры', () {
    final src = File('lib/screens/home_screen.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _handlePairChanged() async {');
    expect(start, greaterThan(0));
    final paired = src.indexOf('if (isPaired) {', start);
    final solo = src.indexOf('} else if (isSolo) {', paired);
    expect(paired, greaterThan(start));
    expect(solo, greaterThan(paired));
    final branch = src.substring(paired, solo);
    expect(branch, contains('_timerService.bindToGroup('));
    expect(branch.contains('_timerService.unbindFromGroup('), isFalse,
        reason: 'отвязка пишет в виджет таймера соло-таймер или пустоту');
  });
}
