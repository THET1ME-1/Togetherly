import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/notif_prefs_sync.dart';

/// Сторож выключателей уведомлений.
///
/// Тумблеры в приложении живут в SharedPreferences и по умолчанию включены, а
/// решает, слать ли пуш, сервер — по колонкам `users.notif_*`. Колонки эти
/// булевы, и у нового аккаунта в них ноль. Пока настройки уезжали только из
/// профиля (`_loadNotifPrefs` в его initState), человек, не открывший вкладку
/// «Профиль», не получал НИ ОДНОГО уведомления: ни чата, ни настроения, ни
/// «Скучаю». На 06.09.2026 таких аккаунтов 18 481, у 7 421 из них живой токен
/// устройства — то есть телефон разрешение дал, а сервер молчал.
///
/// Жалоба «Сообщения в чате не приходят, хотя уведомления включены. Нужно
/// постоянно сидеть в сети, чтобы увидеть» (обращение №133, 06.09.2026).
void main() {
  group('тело запроса', () {
    test('пустые настройки — всё включено, как показывает приложение', () {
      expect(notifPrefsBody(const {}), {
        'notifMissYou': true,
        'notifNewMemory': true,
        'notifMood': true,
        'notifChat': true,
        'notifDraw': true,
        'notifComments': true,
      });
    });

    test('выключенное человеком уезжает выключенным', () {
      final body = notifPrefsBody(const {'notif_chat': false});
      expect(body['notifChat'], isFalse);
      expect(body['notifMood'], isTrue, reason: 'остальное не трогаем');
    });

    test('ключи те же, что пишет профиль', () {
      expect(notifPrefKeys.keys, contains('notif_chat'));
      expect(notifPrefKeys['notif_chat'], 'notifChat');
      expect(notifPrefKeys.length, 6);
    });
  });

  group('утренний сундук', () {
    // Колонка на сервере перевёрнута: у сборок, не знающих про неё, ноль, и
    // ноль обязан значить «присылать».
    test('не трогал тумблер — пуш нужен', () {
      expect(chestPushBody(null), {'notifChestOff': false});
    });

    test('выключил — сервер молчит', () {
      expect(chestPushBody(false), {'notifChestOff': true});
      expect(chestPushBody(true), {'notifChestOff': false});
    });

    test('поле проходит белый список профиля', () {
      final pb = File('lib/services/pb_data_service.dart').readAsStringSync();
      expect(pb.contains("put('notifChestOff', 'notif_chest_off')"), isTrue,
          reason: 'updateUserProfile молча выбрасывает незнакомый ключ');
    });

    test('сервер читает ту же колонку', () {
      final script =
          File('pocketbase/chest_morning_push.py').readAsStringSync();
      expect(script.contains('notif_chest_off'), isTrue);
    });
  });

  group('проводка', () {
    String read(String path) => File(path).readAsStringSync();

    test('настройки уезжают сразу после входа, а не только из профиля', () {
      final home = read('lib/screens/home_screen.dart');
      expect(home.contains('NotifPrefsSync.pushToServer()'), isTrue,
          reason: 'Без этого вызова сервер узнаёт о тумблерах только тогда, '
              'когда человек откроет вкладку «Профиль»');
    });

    test('профиль отправляет настройки тем же кодом', () {
      final profile = read('lib/screens/profile_screen.dart');
      expect(profile.contains('NotifPrefsSync'), isTrue,
          reason: 'Две копии списка колонок разъезжаются: notif_draw и '
              'notif_comments уже были только в одной из них');
    });
  });

  group('вечернее напоминание (TOG-113)', () {
    // Выключатели на сервере перевёрнуты, как у сундука. Время уходит всегда:
    // по нему сервер видит сборку, где напоминание можно выключить, и только
    // ей его шлёт. `remindCustom` — человек сам трогал настройку, тогда
    // напоминаем и без привычки.
    test('не трогал — оба включены, 21:00, по привычке', () {
      expect(eveningReminderBody(mood: null, task: null, at: null, custom: null), {
        'remindMoodOff': false,
        'remindTaskOff': false,
        'remindAt': '21:00',
        'remindCustom': false,
      });
    });

    test('выключил одно и выбрал время', () {
      expect(eveningReminderBody(mood: false, task: true, at: '20:30', custom: true), {
        'remindMoodOff': true,
        'remindTaskOff': false,
        'remindAt': '20:30',
        'remindCustom': true,
      });
    });

    // Выключение не должно включать другое: метка «сам настраивал» снимает
    // порог привычки, и человек, выключивший настроение, начал бы получать
    // «Задание дня ждёт», которого раньше не было.
    test('время в prefs ещё не значит «сам настраивал»', () {
      expect(eveningReminderBody(mood: false, task: true, at: '21:00', custom: null)['remindCustom'],
          isFalse);
    });

    test('время по умолчанию — 21:00', () {
      expect(kEveningReminderDefaultAt, '21:00');
      expect(remindAtMinutes(null), 21 * 60);
    });

    test('время туда и обратно, кривое — как по умолчанию', () {
      expect(remindAtMinutes('20:30'), 20 * 60 + 30);
      expect(remindAtMinutes('7:05'), 7 * 60 + 5);
      expect(remindAtOf(7 * 60 + 5), '07:05');
      expect(remindAtOf(remindAtMinutes('23:59')), '23:59');
      for (final bad in ['', '24:00', '12:60', 'вечер', '21']) {
        expect(remindAtMinutes(bad), 21 * 60, reason: bad);
      }
    });

    test('поля проходят белый список профиля', () {
      final pb = File('lib/services/pb_data_service.dart').readAsStringSync();
      for (final f in [
        "put('remindMoodOff', 'remind_mood_off')",
        "put('remindTaskOff', 'remind_task_off')",
        "put('remindAt', 'remind_at')",
        "put('remindCustom', 'remind_custom')",
      ]) {
        expect(pb.contains(f), isTrue, reason: f);
      }
    });

    test('сервер читает те же колонки', () {
      final script = File('pocketbase/evening_reminder_push.py').readAsStringSync();
      for (final c in ['remind_mood_off', 'remind_task_off', 'remind_at', 'remind_custom']) {
        expect(script.contains(c), isTrue, reason: c);
      }
    });
  });
}
