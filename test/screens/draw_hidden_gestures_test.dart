import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Скрытые приёмы холста не должны срабатывать у человека, который о них
/// не знает.
///
/// Отзыв с iPhone 20.10.2026: «Рисовать просто невозможно, холст живёт своей
/// жизнью». На эмуляторе: волна с задержкой пальца в конце сама становилась
/// прямой (ровные фигуры), а палец, постоявший 0,8 с перед мазком, не рисовал
/// линию и молча перекрашивал кисть в белый цвет холста (пипетка удержанием).
/// Дальше всё рисовалось белым по белому.
void main() {
  final source = File('lib/screens/draw_screen.dart').readAsStringSync();

  test('ровные фигуры по умолчанию выключены', () {
    expect(source, contains('bool _quickShapes = false;'));
    expect(source, contains('p.getBool(UiPrefs.kBrushQuickShapes) ?? false'));
  });

  test('удержание пальца не берёт цвет с холста', () {
    // Пипетка остаётся кнопкой в панели инструментов.
    expect(source, isNot(contains('holdIsEyedropper(')));
  });
}
