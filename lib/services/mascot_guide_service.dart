import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mascot_guide.dart';
import 'pocketbase_service.dart';

/// Включён ли облачко-гид у этого человека и на этом телефоне.
///
/// Поле `app_config.mascot_guide` приезжает в тех же чтениях конфига, что и
/// остальные флаги, и лежит в настройках до следующего запуска: приветствие
/// показывается раньше, чем сервер ответит. Правило — `mascotGuideOn`.
///
/// Телефон, на котором гид хоть раз был включён для вошедшего человека,
/// запоминает это: после выхода из аккаунта приветствие и регистрация на нём
/// тоже с облачком. Иначе владельцу нечем было бы проверить эти экраны.
class MascotGuideService extends ChangeNotifier {
  MascotGuideService._();

  static final MascotGuideService instance = MascotGuideService._();

  static const String _configKey = 'mascot_guide_config';
  static const String _deviceKey = 'mascot_guide_device';

  MascotGuideConfig _config = MascotGuideConfig.off;
  bool _remembered = false;
  bool _restored = false;
  bool _fresh = false;

  /// Поднимает сохранённое. Дешёвый и повторяемый вызов.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _remembered = prefs.getBool(_deviceKey) ?? false;
      final saved = prefs.getString(_configKey);
      // Сервер мог ответить раньше, чем прочитались настройки.
      if (saved != null && !_fresh) _config = MascotGuideConfig.parse(jsonDecode(saved));
      _rememberIfOn();
      notifyListeners();
    } catch (_) {}
  }

  /// Принимает поле `mascot_guide` из записи `app_config`. Сервер без поля
  /// (null) известное не трогает.
  void ingest(Object? raw) {
    if (raw == null) return;
    _fresh = true;
    _config = MascotGuideConfig.parse(raw);
    SharedPreferences.getInstance().then((p) => p.setString(_configKey, jsonEncode(raw))).catchError((_) => false);
    _rememberIfOn();
    notifyListeners();
  }

  /// Человек вошёл (главная открылась): если гид ему включён, телефон это
  /// запоминает сразу, а не когда до гида дойдёт дело.
  void signedIn() => _rememberIfOn();

  /// Кто сейчас вошёл. Тесты подменяют, иначе спрашивается PocketBase.
  @visibleForTesting
  ({String? uid, DateTime? created}) Function()? who;

  ({String? uid, DateTime? created}) _who() {
    final override = who;
    if (override != null) return override();
    final pb = PocketBaseService();
    final rawCreated = pb.currentUser?.data['created'];
    final created = rawCreated is String ? DateTime.tryParse(rawCreated.replaceFirst(' ', 'T')) : null;
    return (uid: pb.userId, created: created);
  }

  /// Гид включён вошедшему по списку или по дате — телефон это запоминает,
  /// чтобы после выхода из аккаунта приветствие осталось с облачком.
  void _rememberIfOn() {
    if (_remembered) return;
    final me = _who();
    if (me.uid == null || !mascotGuideOn(_config, uid: me.uid, createdAt: me.created)) return;
    _remembered = true;
    SharedPreferences.getInstance().then((p) => p.setBool(_deviceKey, true)).catchError((_) => false);
  }

  /// Показывать ли гида сейчас.
  bool get on {
    _rememberIfOn();
    final me = _who();
    return mascotGuideOn(_config, uid: me.uid, createdAt: me.created, rememberedOnDevice: _remembered);
  }

  @visibleForTesting
  void resetForTest() {
    _config = MascotGuideConfig.off;
    _remembered = false;
    _restored = false;
    _fresh = false;
    who = null;
  }
}
