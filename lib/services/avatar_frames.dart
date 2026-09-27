import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pb_data_service.dart';
import 'pocketbase_service.dart';

/// Какая рамка надета на каждого человека, чья аватарка есть на экране.
///
/// Свою рамку сюда кладёт [UserData] (`setMine`). Чужую спрашивает сама
/// аватарка: первый показ человека запускает `/api/user/card` (роут отдаёт
/// карточку только тем, кто с ним в паре), ответ ложится в память и на диск.
/// Поэтому рамка партнёра видна и без сети, а поменял он её — увидишь после
/// следующего запроса, не чаще раза в [_refreshEvery].
///
/// Отдельный реестр, а не поле группы: аватарка рисуется в двух десятках мест
/// и знает только uid, а тянуть рамку в каждое место параметром значило бы
/// забыть её в половине из них.
class AvatarFrames extends ChangeNotifier {
  AvatarFrames._();
  static final AvatarFrames instance = AvatarFrames._();

  static const String _prefsKey = 'avatar_frames_v1';
  static const Duration _refreshEvery = Duration(minutes: 10);

  String? _mine;
  final Map<String, String> _others = {};
  final Map<String, DateTime> _asked = {};
  bool _loaded = false;

  /// Своя надетая рамка. Зовёт [UserData] при загрузке и каждой правке.
  void setMine(String? key) {
    final v = (key == null || key.isEmpty) ? null : key;
    if (v == _mine) return;
    _mine = v;
    notifyListeners();
  }

  /// Рамка человека [uid] или null. Для чужого uid при необходимости
  /// запускает фоновый запрос карточки.
  String? frameOf(String uid) {
    if (uid.isEmpty) return null;
    if (uid == PocketBaseService().userId) return _mine;
    _ensureLoaded();
    _maybeFetch(uid);
    final v = _others[uid];
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Карточку человека уже загрузил кто-то другой (профиль партнёра, экран
  /// связей) — забираем рамку оттуда, второй запрос не нужен.
  void put(String uid, Object? frame) {
    if (uid.isEmpty || uid == PocketBaseService().userId) return;
    final v = frame is String ? frame : '';
    _asked[uid] = DateTime.now();
    if (_others[uid] == v) return;
    _others[uid] = v;
    notifyListeners();
    unawaited(_save());
  }

  void _maybeFetch(String uid) {
    final last = _asked[uid];
    if (last != null && DateTime.now().difference(last) < _refreshEvery) return;
    _asked[uid] = DateTime.now();
    unawaited(() async {
      final card = await PbDataService().loadPartnerCard(uid);
      // Нет ответа (сеть, чужой человек) — держим прежнее знание.
      if (card == null) return;
      put(uid, card['frame']);
    }());
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw == null) return;
        final map = jsonDecode(raw);
        if (map is! Map) return;
        var changed = false;
        for (final e in map.entries) {
          final k = '${e.key}';
          // Свежий ответ сети важнее того, что лежало на диске.
          if (_others.containsKey(k)) continue;
          _others[k] = '${e.value}';
          changed = true;
        }
        if (changed) notifyListeners();
      } catch (_) {}
    }());
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_others));
    } catch (_) {}
  }

  /// Выход из аккаунта: чужие рамки больше не наши.
  Future<void> clear() async {
    _mine = null;
    _others.clear();
    _asked.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  @visibleForTesting
  void debugPut(String uid, String? frame) {
    _loaded = true;
    _asked[uid] = DateTime.now();
    _others[uid] = frame ?? '';
    notifyListeners();
  }
}
