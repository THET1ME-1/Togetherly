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

  group('часовой пояс телефона главнее языка', () {
    test('украинец с телефоном на русском (Россия)', () {
      expect(
        serverRouteWanted(const [Locale('ru', 'RU')], kyivWinter, timeZone: 'Europe/Kyiv'),
        isTrue,
      );
    });

    test('старые и новые имена киевского пояса', () {
      for (final zone in ['Europe/Kiev', 'Europe/Uzhgorod', 'Europe/Zaporozhye']) {
        expect(serverRouteWanted(const [Locale('ru', 'RU')], kyivSummer, timeZone: zone),
            isTrue, reason: zone);
      }
    });

    test('русскоязычный в США', () {
      expect(
        serverRouteWanted(const [Locale('ru', 'RU')], newYork, timeZone: 'America/New_York'),
        isTrue,
      );
      for (final zone in ['America/Indiana/Indianapolis', 'US/Pacific', 'Pacific/Honolulu', 'America/Phoenix']) {
        expect(serverRouteWanted(const [Locale('en', 'US')], losAngeles, timeZone: zone),
            isTrue, reason: zone);
      }
    });

    test('украинский язык в Москве обход не берёт', () {
      expect(
        serverRouteWanted(const [Locale('uk', 'UA')], moscow, timeZone: 'Europe/Moscow'),
        isFalse,
      );
    });

    test('Молдова, Калининград, Крым и Канада обход не берут', () {
      expect(serverRouteWanted(const [Locale('ru', 'RU')], kyivWinter, timeZone: 'Europe/Chisinau'), isFalse);
      expect(serverRouteWanted(const [Locale('ru', 'RU')], kyivWinter, timeZone: 'Europe/Kaliningrad'), isFalse);
      expect(serverRouteWanted(const [Locale('ru', 'UA')], moscow, timeZone: 'Europe/Simferopol'), isFalse);
      expect(serverRouteWanted(const [Locale('en', 'US')], newYork, timeZone: 'America/Toronto'), isFalse);
    });

    test('пояс не узнали — решают язык и регион', () {
      expect(serverRouteWanted(const [Locale('ru', 'UA')], kyivSummer, timeZone: ''), isTrue);
      expect(serverRouteWanted(const [Locale('ru', 'RU')], moscow, timeZone: null), isFalse);
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
