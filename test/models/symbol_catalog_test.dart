import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/symbol_catalog.dart';

/// Символ таймера лежит в `timers.emoji` у всех пар с самого первого релиза.
/// Значение поля мы не мигрируем — новые таймеры пишут туда имя значка, а
/// старые эмодзи разбираются на лету. Эти тесты стерегут разбор: сломается он
/// — у людей пропадут символы, которые они выбирали годами.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SymbolCatalog.load();
  });

  group('Разбор сохранённого значения', () {
    test('Прежние эмодзи превращаются в имена значков', () {
      expect(SymbolCatalog.nameFromStored('❤️'), 'favorite');
      expect(SymbolCatalog.nameFromStored('🎂'), 'cake');
      expect(SymbolCatalog.nameFromStored('✈️'), 'flight');
      expect(SymbolCatalog.nameFromStored('💍'), 'diamond');
      expect(SymbolCatalog.nameFromStored('🎯'), 'track_changes');
    });

    test('Три сердечка сводятся к одному значку', () {
      for (final emoji in ['❤️', '💕', '💖']) {
        expect(SymbolCatalog.nameFromStored(emoji), 'favorite');
      }
    });

    test('Имя значка возвращается как есть', () {
      expect(SymbolCatalog.nameFromStored('rocket_launch'), 'rocket_launch');
      expect(SymbolCatalog.nameFromStored('school'), 'school');
    });

    test('Пустое и неизвестное значение — сердце, а не падение', () {
      expect(SymbolCatalog.nameFromStored(null), 'favorite');
      expect(SymbolCatalog.nameFromStored(''), 'favorite');
      expect(SymbolCatalog.nameFromStored('такого_значка_нет'), 'favorite');
    });
  });

  group('Каталог', () {
    test('Загружен и содержит весь набор', () {
      expect(SymbolCatalog.isLoaded, isTrue);
      expect(SymbolCatalog.names.length, greaterThan(4000));
    });

    test('Быстрый выбор состоит из существующих значков', () {
      for (final name in SymbolCatalog.quickPicks) {
        expect(SymbolCatalog.has(name), isTrue, reason: name);
      }
    });

    test('Каждое имя из русского словаря есть в шрифте', () {
      for (final entry in kSymbolSynonymsRu.entries) {
        for (final name in entry.value) {
          expect(SymbolCatalog.has(name), isTrue,
              reason: '${entry.key} → $name');
        }
      }
    });

    test('Значок берётся из нашего шрифта, а не из встроенного', () {
      expect(SymbolCatalog.iconFor('cake').fontFamily,
          SymbolCatalog.fontFamily);
    });
  });

  group('Поиск', () {
    test('Русское слово находит значок', () {
      expect(searchSymbols('сердце'), contains('favorite'));
      expect(searchSymbols('дом'), contains('home'));
      expect(searchSymbols('торт'), contains('cake'));
    });

    test('Английское имя тоже ищется', () {
      expect(searchSymbols('rocket'), contains('rocket_launch'));
      expect(searchSymbols('cake'), contains('cake'));
    });

    test('Пробел в запросе работает как подчёркивание', () {
      expect(searchSymbols('local fire'), contains('local_fire_department'));
    });

    test('Пустой запрос ничего не ищет', () {
      expect(searchSymbols('   '), isEmpty);
    });
  });
}
