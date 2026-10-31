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
    notifyListeners();
  }

  /// Показывать ли гида сейчас.
  bool get on {
    final pb = PocketBaseService();
    final uid = pb.userId;
    final rawCreated = pb.currentUser?.data['created'];
    final created = rawCreated is String ? DateTime.tryParse(rawCreated.replaceFirst(' ', 'T')) : null;
    final result = mascotGuideOn(_config, uid: uid, createdAt: created, rememberedOnDevice: _remembered);
    // Гид включён вошедшему по списку или по дате — телефон это запоминает.
    if (result && uid != null && !_remembered) {
      _remembered = true;
      SharedPreferences.getInstance().then((p) => p.setBool(_deviceKey, true)).catchError((_) => false);
    }
    return result;
  }
}
