import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/ios_widget_gaps.dart';

/// Две дыры iOS-виджетов, найденные по журналу Bugsink 19 августа 2026.
///
/// Первая: `PlatformException(-5, Interactivity is only available on iOS 17.0)`
/// — 3649 событий за трое суток с версии 1.29.6. Регистрация интерактивного
/// колбэка возвращает Future, и синхронный `try` её отказ не ловит; на iOS 16
/// звать её незачем вовсе.
///
/// Вторая: `ios_photo_day_path` пуст во ВСЕХ самоотчётах — «Фото дня» на
/// айфоне не наполнялось никогда, потому что путь заполнения идёт через список
/// Android-виджетов, а он на iOS всегда пуст.
void main() {
  test('пустой выбор не затирает то, что уже лежит в контейнере', () {
    // Ключи фото-виджетов пишутся ТОЛЬКО когда есть что писать: запись могла не
    // приехать (нет сети, отказ сервера, полумёртвая сессия), и пустая строка
    // стёрла бы снимок с рабочего стола.
    final src = File('lib/services/home_widget_service.dart').readAsStringSync();
    final block = RegExp(
      r"if \(dayPhotoUrl\.isNotEmpty \|\| day\.isNotEmpty\) \{",
    );
    expect(block.hasMatch(src), isTrue,
        reason: 'фото дня пишется без проверки — пустота затрёт прежний снимок');
  });

  group('supportsWidgetInteractivity', () {
    test('iOS 17 и новее — интерактивность есть', () {
      expect(supportsWidgetInteractivity('Version 17.0 (Build 21A329)'), isTrue);
      expect(supportsWidgetInteractivity('Version 18.7.9 (Build 22H123)'),
          isTrue);
      expect(supportsWidgetInteractivity('Version 26.5.2 (Build 23A1)'), isTrue);
    });

    test('iOS 16 и старше — не зовём', () {
      expect(
          supportsWidgetInteractivity('Version 16.7.10 (Build 20H350)'), isFalse);
      expect(supportsWidgetInteractivity('Version 15.8 (Build 19H370)'), isFalse);
    });

    test('строку не разобрали — считаем, что нет', () {
      // Лучше промолчать, чем получить отказ платформы в необработанном виде.
      expect(supportsWidgetInteractivity(''), isFalse);
      expect(supportsWidgetInteractivity('какая-то ерунда'), isFalse);
    });
  });

  group('iosDayPhoto', () {
    test('берём снимок партнёра — он и есть «фото дня»', () {
      final day = iosDayPhoto(
        mine: const ['https://x/my.jpg'],
        theirs: const ['https://x/their.jpg', 'https://x/their2.jpg'],
        myName: 'Я',
        partnerName: 'Кот',
      );
      expect(day.url, 'https://x/their.jpg');
      expect(day.author, 'Кот');
    });

    test('у партнёра пусто — показываем своё', () {
      final day = iosDayPhoto(
        mine: const ['https://x/my.jpg'],
        theirs: const [],
        myName: 'Я',
        partnerName: 'Кот',
      );
      expect(day.url, 'https://x/my.jpg');
      expect(day.author, 'Я');
    });

    test('нет ни одного снимка — пусто, и это не ошибка', () {
      final day = iosDayPhoto(
        mine: null,
        theirs: null,
        myName: 'Я',
        partnerName: 'Кот',
      );
      expect(day.url, isEmpty);
      expect(day.author, isEmpty);
    });

    test('«не знаю» у партнёра не выдаём за «нет»', () {
      // null — запись не приехала (нет сети, отказ сервера). Своим снимком её
      // подменять нельзя: на столе у человека фото партнёра сменилось бы своим.
      final day = iosDayPhoto(
        mine: const ['https://x/my.jpg'],
        theirs: null,
        myName: 'Я',
        partnerName: 'Кот',
      );
      expect(day.url, isEmpty);
    });
  });
}
