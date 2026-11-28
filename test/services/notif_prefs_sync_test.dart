import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/notif_prefs_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('уведомления «А»: метка сборки', () {
    test('сборка с отрисовкой шлёт notifV, без неё — ничего', () {
      // С notif_v сервер шлёт Android пуш только данными: сборка, которая
      // рисовать не умеет, такой пуш не показала бы вовсе.
      expect(notifCoverBody(1), {'notifV': 1});
      expect(notifCoverBody(0), isEmpty);
    });
  });

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
    // При каждом запуске уходят только метка сборки и пояс: по метке сервер
    // узнаёт сборку, где напоминание можно выключить. Выбор человека уходит
    // только после его действия и с отметкой времени — иначе телефон со
    // старым выбором затирал бы при запуске выбор, сделанный на другом.
    test('запуск — только метка сборки и пояс', () {
      expect(eveningReminderBaseBody(tz: 'Europe/Kyiv'), {
        'remindV': kEveningReminderVersion,
        'remindTz': 'Europe/Kyiv',
      });
      expect(eveningReminderBaseBody(tz: null), {'remindV': kEveningReminderVersion});
    });

    test('выбор уходит целиком, нерешённое — пустой строкой', () {
      expect(eveningReminderChoiceBody(mood: 'off', task: null, at: 'вечер', setAt: 42), {
        'remindMood': 'off',
        'remindTask': '',
        'remindAt': '',
        'remindSetAt': 42,
      });
    });

    group('сверка с профилем', () {
      late List<Map<String, dynamic>> pushed;
      Future<bool> push(Map<String, dynamic> body) async {
        pushed.add(body);
        return true;
      }

      Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
        pushed = [];
        SharedPreferences.setMockInitialValues({
          for (final e in values.entries) 'flutter.${e.key}': e.value,
        });
        return SharedPreferences.getInstance();
      }

      test('нет неотправленного — повторяем сервер, включая пустое', () async {
        final prefs = await prefsWith({
          kRemindOwnerPref: 'me',
          kRemindMoodPref: 'on',
          kRemindTaskPref: 'on',
          kRemindAtPref: '20:00',
          kRemindSetAtPref: 100,
        });
        await reconcileEveningReminder(
            {'remindMood': 'off', 'remindTask': '', 'remindAt': '', 'remindSetAt': 200},
            uid: 'me', push: push);
        expect(prefs.getString(kRemindMoodPref), 'off');
        expect(prefs.getString(kRemindTaskPref), isNull);
        expect(prefs.getString(kRemindAtPref), isNull);
        expect(prefs.getInt(kRemindSetAtPref), 200);
        expect(pushed, isEmpty);
      });

      test('свой неотправленный выбор новее сервера — уходит на сервер', () async {
        final prefs = await prefsWith({
          kRemindOwnerPref: 'me',
          kRemindMoodPref: 'off',
          kRemindSetAtPref: 300,
          kRemindPendingPref: true,
        });
        await reconcileEveningReminder({'remindMood': 'on', 'remindSetAt': 200},
            uid: 'me', push: push);
        expect(pushed.single, containsPair('remindMood', 'off'));
        expect(pushed.single, containsPair('remindSetAt', 300));
        expect(prefs.getString(kRemindMoodPref), 'off');
        expect(prefs.getBool(kRemindPendingPref), isFalse);
      });

      // Б меняет без сети, потом А меняет в сети, Б выходит на связь:
      // остаться должен выбор А, хотя у Б он «не отправлен».
      test('выбор с другого телефона позже своего — побеждает он', () async {
        final prefs = await prefsWith({
          kRemindOwnerPref: 'me',
          kRemindMoodPref: 'off',
          kRemindSetAtPref: 100,
          kRemindPendingPref: true,
        });
        await reconcileEveningReminder({'remindMood': 'on', 'remindSetAt': 200},
            uid: 'me', push: push);
        expect(pushed, isEmpty);
        expect(prefs.getString(kRemindMoodPref), 'on');
        expect(prefs.getBool(kRemindPendingPref), isFalse);
      });

      // Сверку зовут без ожидания на каждой загрузке профиля. Нажатие во
      // время неё не должно уйти на сервер прежним значением со свежей
      // отметкой времени — тогда «вкл» осталось бы навсегда (ревью 28.11.2026).
      test('нажатие во время сверки не теряется', () async {
        // Нажатие приходит на любом шаге сверки: сдвигаем его старт.
        final lost = <int>[];
        for (var shift = 0; shift < 30; shift++) {
          final prefs = await prefsWith({kRemindOwnerPref: 'other'});
          final rec = reconcileEveningReminder({'remindMood': 'on', 'remindSetAt': 5},
              uid: 'me', push: push);
          for (var i = 0; i < shift; i++) {
            await Future<void>.value();
          }
          final save = NotifPrefsSync.saveEveningReminder(
              mood: 'off', task: null, at: null, uid: 'me', push: push);
          await Future.wait([rec, save]);
          final ok = prefs.getString(kRemindMoodPref) == 'off' &&
              pushed.isNotEmpty &&
              pushed.last['remindMood'] == 'off' &&
              prefs.getBool(kRemindPendingPref) == false;
          if (!ok) lost.add(shift);
        }
        expect(lost, isEmpty, reason: 'сдвиги, где нажатие пропало');
      });

      test('сбой записи при сверке не роняет её и оставляет выбор неотправленным', () async {
        final prefs = await prefsWith({
          kRemindOwnerPref: 'me',
          kRemindMoodPref: 'off',
          kRemindSetAtPref: 300,
          kRemindPendingPref: true,
        });
        await reconcileEveningReminder({'remindSetAt': 200},
            uid: 'me', push: (_) async => throw StateError('сеть'));
        expect(prefs.getBool(kRemindPendingPref), isTrue);
        expect(prefs.getString(kRemindMoodPref), 'off');
      });

      test('на телефоне вошёл другой аккаунт — чужой выбор не уходит', () async {
        final prefs = await prefsWith({
          kRemindOwnerPref: 'other',
          kRemindMoodPref: 'off',
          kRemindSetAtPref: 900,
          kRemindPendingPref: true,
        });
        await reconcileEveningReminder({}, uid: 'me', push: push);
        expect(pushed, isEmpty);
        expect(prefs.getString(kRemindMoodPref), isNull);
        expect(prefs.getString(kRemindOwnerPref), 'me');
      });
    });

    test('профиль отдаёт поля напоминания', () {
      final pb = File('lib/services/pb_data_service.dart').readAsStringSync();
      for (final f in ["'remindMood': d['remind_mood']", "'remindTask': d['remind_task']",
          "'remindAt': d['remind_at']", "'remindSetAt': d['remind_set_at']"]) {
        expect(pb.contains(f), isTrue, reason: f);
      }
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
        "put('remindV', 'remind_v')",
        "put('remindTz', 'remind_tz')",
        "put('remindMood', 'remind_mood')",
        "put('remindTask', 'remind_task')",
        "put('remindAt', 'remind_at')",
        "put('remindSetAt', 'remind_set_at')",
      ]) {
        expect(pb.contains(f), isTrue, reason: f);
      }
    });

    test('сервер читает те же колонки', () {
      final script = File('pocketbase/evening_reminder_push.py').readAsStringSync();
      for (final c in ['remind_v', 'remind_tz', 'remind_mood', 'remind_task', 'remind_at']) {
        expect(script.contains(c), isTrue, reason: c);
      }
    });
  });
}
