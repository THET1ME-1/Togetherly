import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_layout.dart';

void main() {
  group('раскладка экрана рисования', () {
    test('телефон стоймя держит панель снизу', () {
      expect(drawLayoutFor(const Size(393, 780)), DrawLayout.bottomSheet);
    });

    test('телефон лёжа уводит панель вбок', () {
      expect(drawLayoutFor(const Size(780, 393)), DrawLayout.sidePanel);
    });

    test('почти квадратный экран остаётся с нижней панелью', () {
      // Раскладной телефон и планшет стоймя: высоты хватает, а боковая
      // колонка отняла бы у холста ширину.
      expect(drawLayoutFor(const Size(840, 800)), DrawLayout.bottomSheet);
    });

    test('низкий экран уводит панель вбок даже при равной ширине', () {
      // Нижняя панель занимает около 400 точек: на такой высоте от холста
      // не осталось бы ничего.
      expect(drawLayoutFor(const Size(700, 420)), DrawLayout.sidePanel);
    });

    test('боковая панель не съедает больше трети ширины', () {
      final width = sidePanelWidth(const Size(1000, 500));
      expect(width, lessThanOrEqualTo(1000 / 3));
      expect(width, greaterThanOrEqualTo(300));
    });

    test('на узком экране боковая панель не меньше рабочей ширины', () {
      expect(sidePanelWidth(const Size(720, 360)), 300);
    });
  });
}
