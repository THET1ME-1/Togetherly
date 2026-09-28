import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/ailment.dart';
import 'package:love_app/widgets/common/ailment_icon.dart';

// Значки самочувствия той же рукой, что значки профиля (28.09.2026): у каждого
// самочувствия из сборки есть неподвижный кадр, анимация — из каталога.
void main() {
  test('у каждого самочувствия есть кадр в сборке и он объявлен', () {
    final ids = kAilments.map((a) => a.id).toSet();
    expect(AilmentIcon.bundled, ids);
    for (final id in ids) {
      expect(File('assets/images/ailments/$id.webp').existsSync(), isTrue, reason: id);
    }
    expect(File('pubspec.yaml').readAsStringSync().contains('- assets/images/ailments/'), isTrue);
  });

  testWidgets('без каталога — кадр из сборки, незнакомое — эмодзи', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Row(children: [
        AilmentIcon(id: 'fever', emoji: '🌡️'),
        AilmentIcon(id: 'new_one', emoji: '🥲'),
      ]),
    ));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('🥲'), findsOneWidget);
  });
}
