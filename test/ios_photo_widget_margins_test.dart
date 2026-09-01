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
}
