import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/server_route_country.dart';

// Кому нужен обход для Украины. В 1.39 он стоял у всех, и мгновенная связь не
// поднималась ни у кого (24.10.2026): теперь только там, где сервер режут.
void main() {
  const kyivSummer = Duration(hours: 3);
  const kyivWinter = Duration(hours: 2);
  const moscow = Duration(hours: 3);
  const newYork = Duration(hours: -4);
  const losAngeles = Duration(hours: -7);
  const honolulu = Duration(hours: -10);

  group('Украина', () {
    test('русский язык, регион Украина', () {
      expect(serverRouteWanted(const [Locale('ru', 'UA')], kyivSummer), isTrue);
    });

    test('украинский язык зимой', () {
      expect(serverRouteWanted(const [Locale('uk', 'UA')], kyivWinter), isTrue);
    });

    test('украинский язык без региона', () {
      expect(serverRouteWanted(const [Locale('uk')], kyivSummer), isTrue);
    });

    test('украинский вторым языком', () {
      expect(
        serverRouteWanted(const [Locale('ru', 'RU'), Locale('uk', 'UA')], kyivSummer),
        isTrue,
      );
    });

    test('украинец в Канаде обход не берёт: там сервер не режут', () {
      expect(serverRouteWanted(const [Locale('uk', 'UA')], const Duration(hours: -5)), isFalse);
    });
  });

  group('США', () {
    test('английский, регион США, Нью-Йорк', () {
      expect(serverRouteWanted(const [Locale('en', 'US')], newYork), isTrue);
    });

    test('Лос-Анджелес и Гавайи', () {
      expect(serverRouteWanted(const [Locale('en', 'US')], losAngeles), isTrue);
      expect(serverRouteWanted(const [Locale('en', 'US')], honolulu), isTrue);
    });

    test('телефон на английском в Москве — не американский', () {
      expect(serverRouteWanted(const [Locale('en', 'US')], moscow), isFalse);
    });

    test('английский США вторым языком не в счёт', () {
      expect(
        serverRouteWanted(const [Locale('ru', 'RU'), Locale('en', 'US')], newYork),
        isFalse,
      );
    });
  });

  group('остальным обход не нужен', () {
    test('Россия', () {
      expect(serverRouteWanted(const [Locale('ru', 'RU')], moscow), isFalse);
    });

    test('Молдова', () {
      expect(serverRouteWanted(const [Locale('ru', 'MD')], kyivSummer), isFalse);
      expect(serverRouteWanted(const [Locale('ro', 'MD')], kyivSummer), isFalse);
    });

    test('Германия', () {
      expect(serverRouteWanted(const [Locale('de', 'DE')], const Duration(hours: 2)), isFalse);
    });

    test('язык системы неизвестен', () {
      expect(serverRouteWanted(const [], kyivSummer), isFalse);
    });
  });
}
