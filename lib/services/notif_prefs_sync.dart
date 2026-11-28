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
        ...eveningReminderBody(
          mood: prefs.getBool(kRemindMoodPref),
          task: prefs.getBool(kRemindTaskPref),
          at: prefs.getString(kRemindAtPref),
        ),
        // Метка говорит серверу, что нули в колонках — выбор человека, а не
        // незаполненное поле.
        'notifSyncedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('NotifPrefsSync: настройки не уехали — $e');
    }
  }

  /// Сохранить вечернее напоминание и отправить на сервер. Время пишется при
  /// любой правке: кто трогал эти настройки, тот хочет напоминание, и сервер
  /// перестаёт ждать от него привычки.
  static Future<void> saveEveningReminder({
    required bool mood,
    required bool task,
    required int atMinutes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final at = remindAtOf(atMinutes);
    await prefs.setBool(kRemindMoodPref, mood);
    await prefs.setBool(kRemindTaskPref, task);
    await prefs.setString(kRemindAtPref, at);
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return;
    try {
      await PbDataService().updateUserProfile(
        uid,
        eveningReminderBody(mood: mood, task: task, at: at),
      );
    } catch (e) {
      // Не уехало сейчас — уедет при следующем запуске (pushToServer).
      debugPrint('NotifPrefsSync: напоминание не уехало — $e');
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

/// Вечернее напоминание (TOG-113, `pocketbase/evening_reminder_push.py`):
/// отметить настроение и выполнить задание дня, если за день не сделано.
const String kRemindMoodPref = 'remind_mood';
const String kRemindTaskPref = 'remind_task';

/// Время `ЧЧ:ММ`. Пока человек настройку не трогал, в prefs пусто, и сервер
/// напоминает только по привычке (настроение — хотя бы 4 дня из 14, задание —
/// за последние 3 дня).
const String kRemindAtPref = 'remind_at';
const String kEveningReminderDefaultAt = '21:00';

/// `ЧЧ:ММ` → минуты от полуночи. Пусто или криво — 21:00, как на сервере.
int remindAtMinutes(String? at) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((at ?? '').trim());
  if (m != null) {
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h < 24 && min < 60) return h * 60 + min;
  }
  return 21 * 60;
}

/// Минуты от полуночи → `ЧЧ:ММ` для сервера (всегда 24 часа).
String remindAtOf(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Выключатели на сервере перевёрнуты, как у сундука. Время уходит всегда: по
/// нему сервер узнаёт сборку, где напоминание можно выключить, и шлёт его
/// только ей (у выпущенных раньше выключателя нет). `remindCustom` — человек
/// сам трогал настройку, и тогда напоминаем без привычки.
Map<String, dynamic> eveningReminderBody({
  required bool? mood,
  required bool? task,
  required String? at,
}) {
  final custom = at != null && at.isNotEmpty;
  return {
    'remindMoodOff': !(mood ?? true),
    'remindTaskOff': !(task ?? true),
    'remindAt': custom ? at : kEveningReminderDefaultAt,
    'remindCustom': custom,
  };
}

/// Тело запроса к профилю. Значения нет — значит человек тумблер не трогал, а
/// приложение показывает его включённым; таким и отправляем.
Map<String, dynamic> notifPrefsBody(Map<String, bool?> stored) => {
  for (final e in notifPrefKeys.entries) e.value: stored[e.key] ?? true,
};
