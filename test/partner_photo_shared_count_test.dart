import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_data.dart';

// Обращение 12 в приёмной: партнёр отправил одно фото одиночным полем, карусель
// пуста — а экран «Виджеты» писал «ещё не поделился» и «Нет фото от партнёра»,
// хотя виджет это фото показывал. Счёт шёл через `urls.length ?? одиночное`,
// а список не бывает null, поэтому одиночное поле не учитывалось никогда.
void main() {
  group('WidgetData.sharedPhotoCount', () {
    test('одиночное поле при пустой карусели — одно фото', () {
      final d = WidgetData(uid: 'u', photoForPartnerUrl: 'pb://media/x.webp');
      expect(d.sharedPhotoCount, 1);
    });

    test('карусель считается по длине', () {
      final d = WidgetData(
        uid: 'u',
        photoForPartnerUrl: 'pb://media/a.webp',
        photoForPartnerUrls: const ['a', 'b', 'c'],
      );
      expect(d.sharedPhotoCount, 3);
    });

    test('пусто везде — ноль', () {
      expect(WidgetData(uid: 'u').sharedPhotoCount, 0);
      expect(WidgetData(uid: 'u', photoForPartnerUrl: '').sharedPhotoCount, 0);
    });
  });

  test('экран «Виджеты» не считает фото партнёра через ?? от списка', () {
    final src = File('lib/screens/widget_screen.dart').readAsStringSync();
    expect(src.contains('photoForPartnerUrls.length ??'), isFalse);
  });
}
