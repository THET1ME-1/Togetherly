import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// На iPhone Togetherly+ не существует, и вести туда нельзя ниоткуда.
///
/// Продукта в App Store Connect нет, а внешняя оплата запрещена правилом
/// 3.1.1 — на этом уже ловили реджекты. Поэтому каждый переход на витрину
/// обязан стоять за проверкой доступности: `PlusService.instance.gate`,
/// `visible`, `PlusGate.locked` или переданный флаг. Один забытый вход стоит
/// снятия приложения с продажи, а увидеть его на Android невозможно.
void main() {
  test('витрина Togetherly+ открывается только за проверкой доступа', () {
    final gateRe = RegExp(
        r'PlusGate|PlusService\.instance\.(gate|visible|active)|plusVisible|'
        r'plusGate|shouldShowPlusPromo|_gate');
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (file.path.endsWith('plus_screen.dart')) continue; // сама витрина
      final source = file.readAsStringSync();
      if (!source.contains('PlusScreen(')) continue;
      if (gateRe.hasMatch(source)) continue;
      offenders.add(file.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'переход на витрину без проверки доступности — на iPhone это '
          'реджект 3.1.1: ${offenders.join(', ')}',
    );
  });
}
