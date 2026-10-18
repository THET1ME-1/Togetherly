// «Виджеты на рабочем столе» строится по номерам виджетов Android. На iPhone
// номеров нет, и раздел всегда писал «Виджет ещё не добавлен», хотя виджеты
// стояли на столе (обращение 284, 18.10.2026). На iPhone раздела нет вовсе.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('раздел экземпляров фото-виджетов спрятан на iPhone', () {
    final src = File('lib/screens/widget_screen.dart').readAsStringSync();
    final uses = RegExp(r'widgetInstances,').allMatches(src).toList();
    expect(uses, hasLength(2), reason: 'раздел есть у своих фото и у фото партнёра');
    for (final use in uses) {
      final before = src.substring((use.start - 220).clamp(0, src.length), use.start);
      expect(before, contains('if (!Platform.isIOS)'),
          reason: 'заголовок «Виджеты на рабочем столе» без проверки платформы');
    }
  });
}
