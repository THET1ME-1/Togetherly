// Цикл открывает подписка, а не пол в профиле.
//
// До 8 сентября 2026 карточку видел только женский профиль. Человек с пустым
// полом — а при входе через Google он таким и остаётся — не находил цикл вовсе
// и не получал никакого объяснения: раздела просто не было. В приёмной это
// выглядело как «мы нажали и нету такого» (01.09.2026).
//
// Решение владельца: пол не спрашиваем, условие одно — Togetherly+. Кому
// отметки не нужны, тот их не заводит.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('доступ к циклу не зависит от пола', () {
    final source = File('lib/services/cycle_service.dart').readAsStringSync();
    final start = source.indexOf('static bool availableFor');
    expect(start, greaterThan(-1), reason: 'правило доступа должно быть на месте');
    final rule = source.substring(start, start + 200);

    expect(rule.contains('Gender'), isFalse,
        reason: 'пол в условии доступа больше не участвует');
    expect(rule.contains('PlusService.instance.visible'), isTrue,
        reason: 'условие одно — Togetherly+');
  });
}
