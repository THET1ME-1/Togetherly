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
        // Вечернее напоминание: только метка сборки и пояс. Выбор человека
        // уходит после его действия, иначе этот телефон затирал бы выбор,
        // сделанный на другом (см. [reconcileEveningReminder]).
        ...eveningReminderBaseBody(tz: await deviceTimeZone()),
        // Метка говорит серверу, что нули в колонках — выбор человека, а не
        // незаполненное поле.
        'notifSyncedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('NotifPrefsSync: настройки не уехали — $e');
    }
  }

  /// Выбор человека в вечернем напоминании: записать целиком с отметкой
  /// времени и отправить. Не уехало — останется «неотправленным» и уйдёт при
  /// следующей сверке с профилем, если к тому времени не появился выбор новее.
  static Future<void> saveEveningReminder({
    String? mood,
    String? task,
    String? at,
  }) async {
    final uid = PocketBaseService().userId ?? '';
    final prefs = await SharedPreferences.getInstance();
    await _writeChoice(prefs, mood: mood, task: task, at: at);
    await prefs.setInt(kRemindSetAtPref, DateTime.now().millisecondsSinceEpoch);
    await prefs.setBool(kRemindPendingPref, true);
    await prefs.setString(kRemindOwnerPref, uid);
    if (uid.isEmpty) return;
    if (await _pushChoice(uid, prefs)) {
      await prefs.setBool(kRemindPendingPref, false);
    }
  }
}

Future<bool> _pushChoice(String uid, SharedPreferences prefs) async {
  try {
    return await PbDataService().updateUserProfile(uid, {
      ...eveningReminderBaseBody(tz: await deviceTimeZone()),
      ...eveningReminderChoiceBody(
        mood: prefs.getString(kRemindMoodPref),
        task: prefs.getString(kRemindTaskPref),
        at: prefs.getString(kRemindAtPref),
        setAt: prefs.getInt(kRemindSetAtPref) ?? 0,
      ),
    });
  } catch (e) {
    debugPrint('NotifPrefsSync: напоминание не уехало — $e');
    return false;
  }
}

/// Записать выбор в prefs: годное — как есть, остальное — убрать.
Future<void> _writeChoice(SharedPreferences prefs,
    {String? mood, String? task, String? at}) async {
  final values = {
    kRemindMoodPref: remindModeOf(mood),
    kRemindTaskPref: remindModeOf(task),
    kRemindAtPref: remindAtValid(at),
  };
  for (final e in values.entries) {
    final v = e.value;
    if (v == null) {
      await prefs.remove(e.key);
    } else {
      await prefs.setString(e.key, v);
    }
  }
}

/// Сверить вечернее напоминание телефона с профилем на сервере (при каждой
/// загрузке профиля и при открытии блока настроек).
///
/// Побеждает выбор, сделанный позже (`remindSetAt`), а не тот, что раньше
/// вышел на связь: телефон Б поменял без сети, потом А поменял в сети, Б
/// выходит на связь — остаётся выбор А. Свой неотправленный выбор новее
/// сервера уходит на сервер. Во всех остальных случаях prefs повторяют
/// сервер, включая пустое: на телефоне мог войти другой аккаунт.
///
/// [push] подменяется в тестах; по умолчанию — запись своего профиля.
Future<void> reconcileEveningReminder(
  Map<String, dynamic> profile, {
  required String uid,
  Future<bool> Function(Map<String, dynamic> body)? push,
}) async {
  if (uid.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(kRemindOwnerPref) != uid) {
    // Выбор другого аккаунта: на сервер не уходит, здесь не нужен.
    await _writeChoice(prefs);
    await prefs.remove(kRemindSetAtPref);
    await prefs.setBool(kRemindPendingPref, false);
    await prefs.setString(kRemindOwnerPref, uid);
  }
  final serverSetAt = int.tryParse('${profile['remindSetAt'] ?? 0}') ?? 0;
  final localSetAt = prefs.getInt(kRemindSetAtPref) ?? 0;
  final pending = prefs.getBool(kRemindPendingPref) ?? false;

  if (pending && localSetAt > serverSetAt) {
    final body = eveningReminderChoiceBody(
      mood: prefs.getString(kRemindMoodPref),
      task: prefs.getString(kRemindTaskPref),
      at: prefs.getString(kRemindAtPref),
      setAt: localSetAt,
    );
    final ok = push != null
        ? await push(body)
        : await PbDataService().updateUserProfile(uid, {
            ...eveningReminderBaseBody(tz: await deviceTimeZone()),
            ...body,
          });
    if (ok) await prefs.setBool(kRemindPendingPref, false);
    return;
  }

  await _writeChoice(
    prefs,
    mood: profile['remindMood']?.toString(),
    task: profile['remindTask']?.toString(),
    at: profile['remindAt']?.toString(),
  );
  await prefs.setInt(kRemindSetAtPref, serverSetAt);
  await prefs.setBool(kRemindPendingPref, false);
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

/// Когда человек сделал выбор (мс), есть ли он уже на сервере и чей он:
/// по ним [reconcileEveningReminder] решает, чей выбор новее.
const String kRemindSetAtPref = 'remind_set_at';
const String kRemindPendingPref = 'remind_pending';
const String kRemindOwnerPref = 'remind_owner';

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

/// Уходит при каждом запуске: метка сборки и пояс телефона (пояс нужен и
/// человеку без пары — записи виджета с поясом у него может не быть).
Map<String, dynamic> eveningReminderBaseBody({required String? tz}) => {
      'remindV': kEveningReminderVersion,
      if (tz != null && tz.isNotEmpty) 'remindTz': tz,
    };

/// Выбор человека целиком, с отметкой времени. Нерешённый пункт и время по
/// умолчанию — пустой строкой: выбор заменяет прежний полностью.
Map<String, dynamic> eveningReminderChoiceBody({
  required String? mood,
  required String? task,
  required String? at,
  required int setAt,
}) =>
    {
      'remindMood': remindModeOf(mood) ?? '',
      'remindTask': remindModeOf(task) ?? '',
      'remindAt': remindAtValid(at) ?? '',
      'remindSetAt': setAt,
    };

/// Тело запроса к профилю. Значения нет — значит человек тумблер не трогал, а
/// приложение показывает его включённым; таким и отправляем.
Map<String, dynamic> notifPrefsBody(Map<String, bool?> stored) => {
  for (final e in notifPrefKeys.entries) e.value: stored[e.key] ?? true,
};
