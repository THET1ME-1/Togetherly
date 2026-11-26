import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/xmas_tree.dart';
import 'pocketbase_service.dart';

/// Часы предпросмотра: день из сервера, время суток настоящее.
DateTime previewClock(DateTime day, DateTime real) =>
    DateTime(day.year, day.month, day.day, real.hour, real.minute, real.second);

/// Запрос каталога: включённое, вещи Ту (снятые остаются у владельцев) и —
/// в предпросмотре — спрятанные вещи сезонных наборов [sets]. Имя набора
/// пропускается только из букв, цифр и `_`: оно подставляется в фильтр.
String catalogFilter(List<String> sets) {
  final safe = [for (final s in sets) if (RegExp(r'^[a-z0-9_]+$').hasMatch(s)) s];
  return [
    'enabled = true',
    "kind = 'wear'",
    for (final s in safe) "data.set = '$s'",
  ].join(' || ');
}

/// Предпросмотр сезона (26.11.2026, владелец: «активируй новый год, только
/// мне для теста»). Сервер держит список аккаунтов, которые живут в другом дне
/// (`pb_data/.season_preview.json`, см. `pocketbase/pb_hooks/season_preview.js`):
/// для них сундук открывает сезон этого дня и продаёт спрятанные вещи. Здесь
/// приложение узнаёт свой день (`GET /api/season/preview`) и живёт в нём:
/// часы ёлки ([xtNow]) идут по этому дню, каталог догружает спрятанные
/// наборы. День запоминается в prefs, чтобы при запуске декабрь был сразу,
/// до ответа сервера. Остальным ничего не меняется: ответ пустой.
class SeasonPreview {
  SeasonPreview._();

  static const _kDay = 'season_preview_day', _kSets = 'season_preview_sets';
  static DateTime? _day;
  static List<String> _sets = const [];

  /// Спрятанные наборы, которые этому человеку видны в каталоге.
  static List<String> get sets => _sets;
  static bool get active => _day != null;

  /// Растёт, когда день или наборы поменялись: главная и экраны, зависящие
  /// от даты (ёлка), перерисовываются сразу, без перезапуска приложения.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void _install() {
    final day = _day;
    xtNow = day == null ? DateTime.now : () => previewClock(day, DateTime.now());
  }

  /// День из прошлого запуска — до сети.
  static Future<void> loadSaved() async {
    final p = await SharedPreferences.getInstance();
    _day = DateTime.tryParse(p.getString(_kDay) ?? '');
    _sets = _day == null ? const [] : (p.getStringList(_kSets) ?? const []);
    _install();
  }

  /// Ответ сервера: пустой день — предпросмотра нет, настоящий календарь.
  static Future<void> apply(Map<String, dynamic> res) async {
    final day = DateTime.tryParse('${res['day'] ?? ''}');
    final sets = [for (final s in (res['sets'] as List? ?? const [])) '$s'];
    final before = '${_day?.toIso8601String()}|${_sets.join(',')}';
    _day = day;
    _sets = day == null ? const [] : sets;
    _install();
    if (before != '${_day?.toIso8601String()}|${_sets.join(',')}') changes.value++;
    final p = await SharedPreferences.getInstance();
    if (day == null) {
      await p.remove(_kDay);
      await p.remove(_kSets);
    } else {
      await p.setString(_kDay, '${res['day']}');
      await p.setStringList(_kSets, _sets);
    }
  }

  /// Спросить сервер; true — набор поменялся (каталог стоит перечитать).
  static Future<bool> refresh() async {
    final before = '${_day?.toIso8601String()}|${_sets.join(',')}';
    try {
      final res = await PocketBaseService().pb.send('/api/season/preview');
      if (res is Map) await apply(res.cast<String, dynamic>());
    } catch (_) {
      return false;
    }
    return before != '${_day?.toIso8601String()}|${_sets.join(',')}';
  }

  static void debugReset() {
    _day = null;
    _sets = const [];
    xtNow = DateTime.now;
  }
}
