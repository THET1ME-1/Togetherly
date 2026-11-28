import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_time_zone.dart';
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
          mood: prefs.getString(kRemindMoodPref),
          task: prefs.getString(kRemindTaskPref),
          at: prefs.getString(kRemindAtPref),
          tz: await deviceTimeZone(),
        ),
        // Метка говорит серверу, что нули в колонках — выбор человека, а не
        // незаполненное поле.
        'notifSyncedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('NotifPrefsSync: настройки не уехали — $e');
    }
  }

  /// Записать выбор в вечернем напоминании и отправить на сервер всё, что
  /// выбрано к этому моменту. null — пункт не трогаем.
  static Future<void> saveEveningReminder({
    String? mood,
    String? task,
    String? at,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (remindModeOf(mood) case final v?) await prefs.setString(kRemindMoodPref, v);
    if (remindModeOf(task) case final v?) await prefs.setString(kRemindTaskPref, v);
    if (remindAtValid(at) case final v?) await prefs.setString(kRemindAtPref, v);
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return;
    try {
      await PbDataService().updateUserProfile(
        uid,
        eveningReminderBody(
          mood: prefs.getString(kRemindMoodPref),
          task: prefs.getString(kRemindTaskPref),
          at: prefs.getString(kRemindAtPref),
          tz: await deviceTimeZone(),
        ),
      );
    } catch (e) {
      // Не уехало сейчас — уедет при следующем запуске (pushToServer).
      debugPrint('NotifPrefsSync: напоминание не уехало — $e');
    }
  }
}

/// Пустые prefs вечернего напоминания заполнить выбором с сервера (второе
/// устройство, переустановка). Выбранное на этом телефоне не трогается.
Future<void> adoptEveningReminder(Map<String, dynamic> profile) async {
  final prefs = await SharedPreferences.getInstance();
  final pairs = {
    kRemindMoodPref: remindModeOf(profile['remindMood']?.toString()),
    kRemindTaskPref: remindModeOf(profile['remindTask']?.toString()),
    kRemindAtPref: remindAtValid(profile['remindAt']?.toString()),
  };
  for (final e in pairs.entries) {
    final value = e.value;
    if (value != null && prefs.getString(e.key) == null) {
      await prefs.setString(e.key, value);
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
///
/// У каждого пункта три режима: `on`, `off` или пусто — «по привычке» (сервер
/// напоминает, если настроение отмечено хотя бы 4 дня из 14, задание пара
/// делала за последние 3 дня). Пусто бывает только у того, кто блок настроек
/// не открывал: первый показ записывает положение выключателей явно, иначе
/// экран показывал бы одно, а сервер делал другое.
const String kRemindMoodPref = 'remind_mood_mode';
const String kRemindTaskPref = 'remind_task_mode';

/// Время `ЧЧ:ММ`; пусто — 21:00. Пишется только выбором человека.
const String kRemindAtPref = 'remind_at';
const String kEveningReminderDefaultAt = '21:00';

/// Метка «сборка знает напоминание» (`users.remind_v`). Уходит всегда: только
/// таким сборкам сервер его шлёт — у выпущенных раньше выключателя нет.
const int kEveningReminderVersion = 1;

/// `on`/`off` или null для всего остального.
String? remindModeOf(String? v) => v == 'on' || v == 'off' ? v : null;

/// Годное `ЧЧ:ММ` или null.
String? remindAtValid(String? at) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((at ?? '').trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  return h < 24 && min < 60 ? remindAtOf(h * 60 + min) : null;
}

/// `ЧЧ:ММ` → минуты от полуночи. Пусто или криво — 21:00, как на сервере.
int remindAtMinutes(String? at) {
  final valid = remindAtValid(at);
  if (valid == null) return 21 * 60;
  final parts = valid.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Минуты от полуночи → `ЧЧ:ММ` для сервера (всегда 24 часа).
String remindAtOf(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Тело запроса к профилю. Метка сборки и пояс телефона уходят всегда (пояс
/// нужен и человеку без пары: записи виджета с поясом у него может не быть).
/// Пункты и время — только выбранные: пустой телефон (второе устройство,
/// переустановка) иначе затёр бы выбор человека значениями по умолчанию.
Map<String, dynamic> eveningReminderBody({
  required String? mood,
  required String? task,
  required String? at,
  required String? tz,
}) {
  final m = remindModeOf(mood);
  final t = remindModeOf(task);
  final a = remindAtValid(at);
  return {
    'remindV': kEveningReminderVersion,
    if (tz != null && tz.isNotEmpty) 'remindTz': tz,
    'remindMood': ?m,
    'remindTask': ?t,
    'remindAt': ?a,
  };
}

/// Тело запроса к профилю. Значения нет — значит человек тумблер не трогал, а
/// приложение показывает его включённым; таким и отправляем.
Map<String, dynamic> notifPrefsBody(Map<String, bool?> stored) => {
  for (final e in notifPrefKeys.entries) e.value: stored[e.key] ?? true,
};
