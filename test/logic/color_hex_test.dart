// Разбор и запись HEX для колор-пикера рисования. Пользователь вводит цвет
// руками, поэтому строка приходит какой угодно: с решёткой и без, в любом
// регистре, тремя знаками или шестью, иногда с мусором по краям.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/color_hex.dart';

void main() {
  group('ColorHex.parse', () {
    test('шесть знаков с решёткой', () {
      expect(ColorHex.parse('#FF8800'), const Color(0xFFFF8800));
    });

    test('шесть знаков без решётки', () {
      expect(ColorHex.parse('FF8800'), const Color(0xFFFF8800));
    });

    test('нижний регистр', () {
      expect(ColorHex.parse('#ff8800'), const Color(0xFFFF8800));
    });

    test('три знака разворачиваются в шесть', () {
      expect(ColorHex.parse('#f80'), const Color(0xFFFF8800));
    });

    test('восемь знаков — с прозрачностью', () {
      expect(ColorHex.parse('#80FF8800'), const Color(0x80FF8800));
    });

    test('пробелы по краям не мешают', () {
      expect(ColorHex.parse('  #FF8800 '), const Color(0xFFFF8800));
    });

    test('незаконченный ввод — null', () {
      expect(ColorHex.parse('#FF88'), isNull);
    });

    test('не-шестнадцатеричные знаки — null', () {
      expect(ColorHex.parse('#GG8800'), isNull);
    });

    test('пустая строка — null', () {
      expect(ColorHex.parse(''), isNull);
      expect(ColorHex.parse('#'), isNull);
    });
  });

  group('ColorHex.format', () {
    test('шесть знаков в верхнем регистре с решёткой', () {
      expect(ColorHex.format(const Color(0xFFFF8800)), '#FF8800');
    });

    test('прозрачность отбрасывается', () {
      expect(ColorHex.format(const Color(0x80FF8800)), '#FF8800');
    });

    test('чёрный не теряет нули', () {
      expect(ColorHex.format(const Color(0xFF000000)), '#000000');
    });

    test('запись и разбор возвращают тот же цвет', () {
      const source = Color(0xFF3B82F6);
      expect(ColorHex.parse(ColorHex.format(source)), source);
    });
  });
}
