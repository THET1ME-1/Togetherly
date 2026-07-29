import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Каталог значков Material Symbols: 4334 имени и их кодпоинты.
///
/// Значок таймера раньше выбирался из шестнадцати эмодзи. Эмодзи рисует
/// система: набор свой на каждом телефоне, цвет мимо палитры пары, в тёмной
/// теме — яркое пятно. Теперь символ берётся из шрифта
/// `MaterialSymbolsRounded` (`assets/fonts`), красится ролью схемы и живёт в
/// одном весе с остальным интерфейсом.
///
/// Карта имён лежит в ассете, а не константой в коде: она нужна только экрану
/// выбора, и 4334 строки в Dart компилировались бы в каждую сборку впустую.
abstract final class SymbolCatalog {
  /// Семейство шрифта. Совпадает с `pubspec.yaml`.
  static const String fontFamily = 'MaterialSymbolsRounded';

  static const String _assetPath = 'assets/symbols/material_symbols.json';

  static Map<String, int>? _codes;

  /// Загружен ли каталог. До загрузки [iconFor] отдаёт запасной значок.
  static bool get isLoaded => _codes != null;

  /// Читает карту из ассета. Повторный вызов ничего не делает.
  static Future<void> load() async {
    if (_codes != null) return;
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = json.decode(raw) as Map<String, dynamic>;
    _codes = {
      for (final entry in decoded.entries) entry.key: entry.value as int,
    };
  }

  /// Все имена символов — для поиска на экране выбора.
  static Iterable<String> get names => _codes?.keys ?? const [];

  /// Значок по имени. Неизвестное имя (старая версия, опечатка) — сердце:
  /// таймер без символа выглядит сломанным, а падать из-за значка нельзя.
  static IconData iconFor(String? name) {
    final code = name == null ? null : _codes?[name];
    if (code == null) return _fallbackIcon;
    return IconData(code, fontFamily: fontFamily);
  }

  /// Есть ли такой символ в каталоге.
  static bool has(String name) => _codes?.containsKey(name) ?? false;

  static const IconData _fallbackIcon =
      IconData(0xe87e, fontFamily: fontFamily); // favorite

  /// Что показываем в редакторе таймера без захода в полный список. Пять
  /// поводов, ради которых таймеры и заводят.
  static const List<String> quickPicks = [
    'favorite',
    'local_fire_department',
    'star',
    'cake',
    'home',
  ];

  /// Прежние шестнадцать эмодзи — в имена символов. Значение поля
  /// `timers.emoji` менять миграцией нельзя: оно уже лежит в базе у всех пар,
  /// и старая версия приложения должна продолжать его понимать. Поэтому новые
  /// таймеры пишут туда ИМЯ символа, а старые значения разбираются этой
  /// таблицей на лету.
  static const Map<String, String> _legacyEmoji = {
    '❤️': 'favorite',
    '💕': 'favorite',
    '💖': 'favorite',
    '🔥': 'local_fire_department',
    '⭐': 'star',
    '🌙': 'dark_mode',
    '🎂': 'cake',
    '🏠': 'home',
    '🎓': 'school',
    '💼': 'work',
    '✈️': 'flight',
    '🐾': 'pets',
    '🌸': 'spa',
    '💍': 'diamond',
    '👶': 'child_care',
    '🎯': 'track_changes',
  };

  /// Разбор сохранённого значения: имя символа или эмодзи старого формата.
  static String nameFromStored(String? stored) {
    if (stored == null || stored.isEmpty) return 'favorite';
    final legacy = _legacyEmoji[stored.trim()];
    if (legacy != null) return legacy;
    return has(stored) ? stored : 'favorite';
  }
}

/// Значок из каталога. Отдельный виджет, потому что до загрузки карты
/// (`SymbolCatalog.load`) кодпоинта ещё нет, а рисовать надо уже сейчас.
class SymbolIcon extends StatelessWidget {
  const SymbolIcon(this.name, {super.key, this.size = 24, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(SymbolCatalog.iconFor(name), size: size, color: color);
  }
}

/// Русские слова к именам символов — чтобы поиск работал на языке, на котором
/// человек думает. Здесь только ходовое; чего нет в словаре, ищется по
/// английскому имени самого символа.
const Map<String, List<String>> kSymbolSynonymsRu = {
  'сердце': ['favorite', 'heart_plus', 'volunteer_activism', 'favorite_border'],
  'любовь': ['favorite', 'volunteer_activism', 'diamond', 'celebration'],
  'дом': ['home', 'house', 'cottage', 'castle', 'apartment', 'door_front'],
  'торт': ['cake', 'celebration'],
  'праздник': ['celebration', 'cake', 'festival', 'local_activity'],
  'кольцо': ['diamond', 'workspace_premium'],
  'свадьба': ['diamond', 'church', 'celebration', 'favorite'],
  'ребёнок': ['child_care', 'crib', 'stroller', 'pregnant_woman'],
  'ребенок': ['child_care', 'crib', 'stroller', 'pregnant_woman'],
  'семья': ['family_restroom', 'diversity_1', 'diversity_3'],
  'звезда': ['star', 'stars', 'auto_awesome', 'grade'],
  'огонь': ['local_fire_department', 'whatshot', 'bolt'],
  'луна': ['dark_mode', 'bedtime', 'nights_stay'],
  'солнце': ['sunny', 'light_mode', 'wb_sunny'],
  'цветок': ['spa', 'local_florist', 'yard'],
  'самолёт': ['flight', 'flight_takeoff', 'travel_explore'],
  'самолет': ['flight', 'flight_takeoff', 'travel_explore'],
  'путешествие': ['luggage', 'travel_explore', 'map', 'flight'],
  'море': ['beach_access', 'pool', 'sailing', 'anchor'],
  'гора': ['landscape', 'terrain', 'hiking'],
  'работа': ['work', 'business_center', 'badge', 'handshake'],
  'учёба': ['school', 'menu_book', 'auto_stories', 'backpack'],
  'учеба': ['school', 'menu_book', 'auto_stories', 'backpack'],
  'книга': ['menu_book', 'auto_stories', 'book', 'import_contacts'],
  'музыка': ['music_note', 'headphones', 'library_music', 'piano'],
  'кино': ['movie', 'theaters', 'local_movies', 'smart_display'],
  'игра': ['sports_esports', 'casino', 'extension'],
  'кофе': ['local_cafe', 'coffee', 'emoji_food_beverage'],
  'еда': ['restaurant', 'local_dining', 'lunch_dining', 'ramen_dining'],
  'спорт': ['fitness_center', 'directions_run', 'sports_soccer'],
  'машина': ['directions_car', 'commute', 'local_taxi', 'two_wheeler'],
  'поезд': ['train', 'directions_railway', 'tram'],
  'кот': ['pets', 'cruelty_free'],
  'собака': ['pets'],
  'лапа': ['pets'],
  'подарок': ['card_giftcard', 'redeem'],
  'письмо': ['mail', 'drafts', 'outgoing_mail'],
  'фото': ['photo_camera', 'photo_library', 'image'],
  'кубок': ['emoji_events', 'military_tech', 'workspace_premium'],
  'цель': ['track_changes', 'flag', 'sports_score'],
  'ключ': ['key', 'vpn_key', 'lock_open'],
  'деньги': ['savings', 'payments', 'wallet', 'monetization_on'],
  'время': ['schedule', 'hourglass_top', 'timer', 'calendar_month'],
  'ракета': ['rocket_launch', 'rocket'],
  'переезд': ['local_shipping', 'home_work', 'key'],
  'здоровье': ['health_and_safety', 'medical_services', 'ecg_heart'],
  'зима': ['ac_unit', 'severe_cold'],
  'лето': ['sunny', 'beach_access', 'icecream'],
};

/// Поиск символов по строке. Сначала русские синонимы, потом английские имена.
/// Порядок сохраняем: совпавшее по словарю человек ищет чаще.
List<String> searchSymbols(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final found = <String>{};
  kSymbolSynonymsRu.forEach((word, symbols) {
    if (word.startsWith(q) || q.startsWith(word)) {
      for (final s in symbols) {
        if (SymbolCatalog.has(s)) found.add(s);
      }
    }
  });
  final needle = q.replaceAll(' ', '_');
  for (final name in SymbolCatalog.names) {
    if (name.contains(needle)) found.add(name);
  }
  return found.toList();
}
