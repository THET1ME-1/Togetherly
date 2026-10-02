import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pb_data_service.dart';
import 'pocketbase_service.dart';

/// Выключатели уведомлений: из телефона на сервер.
///
/// Тумблеры живут в SharedPreferences и по умолчанию включены, а пуш шлёт
/// сервер — по колонкам `users.notif_*`. Колонки булевы, у нового аккаунта в
/// них ноль, и до 06.09.2026 отправлял их только экран профиля. Кто не открывал
/// вкладку «Профиль», не получал ничего: ни сообщений чата, ни настроения, ни
/// «Скучаю» — при том что в приложении все тумблеры показаны включёнными.
/// Таких аккаунтов было 18 481, у 7 421 из них живой токен устройства.
class NotifPrefsSync {
  const NotifPrefsSync._();

  /// Отправить текущие тумблеры в свой профиль. Без сессии молчит: отправим
  /// при следующем запуске, когда вход уже будет.
  static Future<void> pushToServer() async {
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = {
      for (final key in notifPrefKeys.keys) key: prefs.getBool(key),
    };
    try {
      await PbDataService().updateUserProfile(uid, {
        ...notifPrefsBody(stored),
        ...chestPushBody(prefs.getBool(kNotifChestPref)),
        // Метка говорит серверу, что нули в колонках — выбор человека, а не
        // незаполненное поле.
        'notifSyncedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('NotifPrefsSync: настройки не уехали — $e');
    }
  }
}

/// Ключ в SharedPreferences → поле профиля. Список один на всё приложение:
/// две копии разъезжались, и `notif_draw` с `notif_comments` какое-то время
/// жили только в одной из них.
const Map<String, String> notifPrefKeys = {
  'notif_miss_you': 'notifMissYou',
  'notif_new_memory': 'notifNewMemory',
  'notif_mood': 'notifMood',
  'notif_chat': 'notifChat',
  'notif_draw': 'notifDraw',
  'notif_comments': 'notifComments',
};

/// Утренний пуш «Сундук снова полный» (`pocketbase/chest_morning_push.py`).
/// На сервере колонка ПЕРЕВЁРНУТА — `notif_chest_off`: новое булево поле у
/// всех ноль, и прямая колонка выключила бы пуш каждому, чья сборка про неё
/// не знает. Ноль в `notif_chest_off` значит «присылать».
const String kNotifChestPref = 'notif_chest';

Map<String, dynamic> chestPushBody(bool? stored) =>
    {'notifChestOff': !(stored ?? true)};

/// Тело запроса к профилю. Значения нет — значит человек тумблер не трогал, а
/// приложение показывает его включённым; таким и отправляем.
Map<String, dynamic> notifPrefsBody(Map<String, bool?> stored) => {
  for (final e in notifPrefKeys.entries) e.value: stored[e.key] ?? true,
};
