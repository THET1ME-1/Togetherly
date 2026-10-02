import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_layout.dart';
import 'plus_service.dart';

/// Хранит раскладку главной ([HomeLayout]) на телефоне и раздаёт её экранам.
///
/// Раскладка своя у каждого телефона и с сервером не синкается: это то, как
/// человеку удобно смотреть на приложение, а не данные пары.
///
/// Слушать нужно этот сервис И [PlusService]: раскладка действует только с
/// Плюсом, [current] учитывает это сам.
class HomeLayoutService extends ChangeNotifier {
  HomeLayoutService._();
  static final HomeLayoutService instance = HomeLayoutService._();

  static const String _prefsKey = 'home_layout_v1';

  HomeLayout _saved = const HomeLayout();
  bool _loaded = false;

  /// То, что человек настроил, без учёта Плюса — для экрана настройки.
  HomeLayout get saved => _saved;

  /// То, что действует на главной сейчас.
  HomeLayout get current =>
      _saved.effective(plus: PlusService.instance.active);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      _saved = HomeLayout.fromJson(jsonDecode(raw));
      notifyListeners();
    } catch (_) {}
  }

  void update(HomeLayout next) {
    _saved = next;
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_saved.toJson()));
    } catch (_) {}
  }

  /// Выход из аккаунта: следующий человек на телефоне видит главную целиком.
  Future<void> clear() async {
    _saved = const HomeLayout();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  @visibleForTesting
  void debugSet(HomeLayout layout) {
    _loaded = true;
    _saved = layout;
    notifyListeners();
  }
}
