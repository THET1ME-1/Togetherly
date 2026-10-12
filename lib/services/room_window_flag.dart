import 'package:shared_preferences/shared_preferences.dart';

import '../models/room_window.dart';

/// Доля людей на iPhone, которым комната открывается нативным окном.
///
/// Приезжает полем `app_config.room_native_ios` в тех же чтениях конфига, что
/// уже идут на главной, и лежит в настройках до следующего запуска: комнату
/// открывают и без сети до сервера конфига. Правило — `roomOpensNatively`.
class RoomWindowFlag {
  RoomWindowFlag._();

  static const String _prefsKey = 'room_native_ios_share';

  /// Проценты 0…100. Ноль — прежнее встроенное окно у всех.
  static int share = 0;

  static bool _restored = false;

  /// Поднимает сохранённую долю. Вызов дешёвый и повторяемый.
  static Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_prefsKey);
      // Сервер мог ответить раньше, чем прочитались настройки.
      if (saved != null && !_fresh) share = roomNativeShare(saved);
    } catch (_) {}
  }

  static bool _fresh = false;

  /// Принимает поле `room_native_ios` из записи `app_config`. Сервер без
  /// поля (null) известное не трогает; ноль — честное «выключить».
  static void ingest(Object? raw) {
    if (raw == null) return;
    _fresh = true;
    final next = roomNativeShare(raw);
    if (next == share) return;
    share = next;
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_prefsKey, next))
        .catchError((_) => false);
  }
}
