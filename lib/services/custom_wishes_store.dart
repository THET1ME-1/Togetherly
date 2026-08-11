import 'package:shared_preferences/shared_preferences.dart';

/// Свои пожелания для быстрого повтора («Купи мне кофе»).
///
/// Список личный и локальный: он короткий, живёт на телефоне и не уезжает на
/// сервер. Порядок — most-recently-used: последнее отправленное встаёт первым,
/// потому что его же чаще всего шлют снова.
class CustomWishesStore {
  static const String prefsKey = 'miss_you_custom_wishes';
  static const int maxWishes = 3;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(prefsKey) ?? const [];
  }

  static Future<List<String>> add(List<String> current, String text) async {
    final next = withWish(current, text);
    await _write(next);
    return next;
  }

  static Future<List<String>> remove(List<String> current, String text) async {
    final next = List<String>.from(current)..remove(text);
    await _write(next);
    return next;
  }

  static Future<void> _write(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefsKey, list);
  }
}

/// Чистое правило списка: дедуп без учёта регистра, свежее в начало, обрезка до
/// [CustomWishesStore.maxWishes]. Пустая строка список не меняет.
List<String> withWish(List<String> current, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return List<String>.from(current);
  final list = List<String>.from(current)
    ..removeWhere((w) => w.toLowerCase() == trimmed.toLowerCase());
  list.insert(0, trimmed);
  while (list.length > CustomWishesStore.maxWishes) {
    list.removeLast();
  }
  return list;
}
