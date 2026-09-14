// Снимок занимает виджет целиком, без белой рамки по краям.
//
// Письмо 26.08.2026 со снимком экрана: «у виджета с фото очень толстые белые
// рамки, которые выглядят не очень». Рамка системная: с iOS 17 виджету
// отводятся поля вокруг содержимого, фотография сжимается внутрь, а по краям
// остаётся фон контейнера. Снимок и есть виджет — поля ему не нужны.
//
// Текстовым виджетам поля нужны, поэтому сторож смотрит только на фото-.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('ios/TogetherlyWidget/PhotoWidgets.swift').readAsStringSync();

  group('Фото-виджеты iOS без системных полей', () {
    for (final widget in const [
      'PhotoGridWidget',
      'SelfPhotoWidgetConfigurable',
      'PartnerPhotoWidgetConfigurable',
      'PhotoDayWidgetConfigurable',
    ]) {
      test('$widget снимает поля', () {
        final start = src.indexOf('struct $widget: Widget {');
        expect(start, greaterThan(0), reason: 'виджет $widget не найден');
        final end = src.indexOf('\n}', start);
        final body = src.substring(start, end);
        expect(body.contains('.contentMarginsDisabled()'), isTrue,
            reason: 'без этого система рисует белую рамку вокруг фото');
      });
    }

    test('фотография растягивается на всю площадь', () {
      expect(src.contains('.scaledToFill()'), isTrue);
    });
  });

  // Снимок с iPhone 14.09.2026: левое фото на пол-виджета больше правого,
  // сверху и снизу белые полосы. Ширину половин меряет рендер
  // (tool/widget_layout, воркфлоу ios-widget-layout.yml), здесь — быстрый
  // сторож тех же двух ошибок по исходнику.
  group('Парный виджет iOS', () {
    final love =
        File('ios/TogetherlyWidget/LoveWidget.swift').readAsStringSync();

    test('снимает системные поля', () {
      final start = love.indexOf('struct LoveWidget: Widget {');
      expect(start, greaterThan(0));
      final body = love.substring(start, love.indexOf('\n}', start));
      expect(body.contains('.contentMarginsDisabled()'), isTrue,
          reason: 'без этого сверху и снизу белые полосы фона');
    });

    test('фото не держится гибкой рамкой', () {
      final flexAfterFill = RegExp(
          r'\.scaledToFill\(\)\s*\.frame\(maxWidth:\s*\.infinity');
      expect(flexAfterFill.hasMatch(love), isFalse,
          reason: 'гибкая рамка принимает ширину широкого фото, '
              'и половины выходят неравными');
    });
  });
}
