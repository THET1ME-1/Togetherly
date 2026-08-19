import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pb_data_service.dart';
import 'pocketbase_service.dart';

/// Свои пожелания для быстрого повтора («Купи мне кофе»).
///
/// Список личный и короткий, порядок — most-recently-used: последнее
/// отправленное встаёт первым, потому что его же чаще всего шлют снова.
///
/// Живёт и на телефоне, и на аккаунте (`users.miss_you_wishes`). Пока он был
/// только в prefs, переустановка стирала его начисто, а на втором устройстве
/// его не было вовсе — человек заново придумывал слова, которые уже придумал
/// однажды.
class CustomWishesStore {
  static const String prefsKey = 'miss_you_custom_wishes';
  static const int maxWishes = 3;

  /// Список для экрана: сперва свой, затем — что знает аккаунт.
  ///
  /// Сеть не ждём молча: телефонный список отдаётся сразу, серверный приезжает
  /// следующим вызовом [pull]. Так экран не висит на медленной связи.
  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return normalize(prefs.getStringList(prefsKey) ?? const []);
  }

  /// Забирает список с аккаунта и кладёт его на телефон.
  ///
  /// Возвращает то, что показывать. Сервер молчит или отдаёт пустоту — остаётся
  /// своё (см. [mergeCustomWishes]).
  static Future<List<String>> pull(List<String> local) async {
    try {
      final uid = PocketBaseService().userId ?? '';
      if (uid.isEmpty) return local;
      final rec = await PbDataService().loadUserProfile(uid);
      final raw = rec?.data['miss_you_wishes'];
      final merged = mergeCustomWishes(
        local: local,
        remote: raw is List ? raw : null,
      );
      if (!listEquals(merged, local)) await _write(merged);
      return merged;
    } catch (e) {
      debugPrint('CustomWishesStore.pull failed: $e');
      return local;
    }
  }

  /// Кладёт список на аккаунт. Ответа не ждём: список короткий и не
  /// экономический, а экран должен отвечать сразу.
  static Future<void> push(List<String> list) async {
    try {
      final uid = PocketBaseService().userId ?? '';
      if (uid.isEmpty) return;
      await PbDataService().updateUserProfile(uid, {'missYouWishes': list});
    } catch (e) {
      debugPrint('CustomWishesStore.push failed: $e');
    }
  }

  static Future<List<String>> add(List<String> current, String text) async {
    final next = withWish(current, text);
    await _write(next);
    unawaited(push(next));
    return next;
  }

  static Future<List<String>> remove(List<String> current, String text) async {
    final next = List<String>.from(current)..remove(text);
    await _write(next);
    unawaited(push(next));
    return next;
  }

  static Future<void> _write(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefsKey, list);
  }

  /// Кладёт список на телефон, не трогая сервер (его правит вызывающий).
  static Future<void> replace(List<String> list) => _write(normalize(list));
}

/// Приводит присланное к виду списка: строки, без пустых и повторов, не длиннее
/// потолка. Через это проходит всё, что приезжает с сервера, — в json-поле
/// может лежать что угодно.
List<String> normalize(Iterable<dynamic> raw) {
  final out = <String>[];
  for (final item in raw) {
    if (item is! String) continue;
    final text = item.trim();
    if (text.isEmpty) continue;
    if (out.any((w) => w.toLowerCase() == text.toLowerCase())) continue;
    out.add(text);
    if (out.length >= CustomWishesStore.maxWishes) break;
  }
  return out;
}

/// Что показать человеку: серверный список или свой.
///
/// `null` у [remote] означает «поле не приехало» — нет сети, старая сборка,
/// отказ сервера. Пустой серверный список тоже не повод стирать своё: пожелание
/// могли завести без сети, и оно ещё не уехало на аккаунт. Тот же приём, что у
/// своих тем.
List<String> mergeCustomWishes({
  required List<String> local,
  required List<dynamic>? remote,
}) {
  if (remote == null) return normalize(local);
  final fromServer = normalize(remote);
  if (fromServer.isEmpty) return normalize(local);
  return fromServer;
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
