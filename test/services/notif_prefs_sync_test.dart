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
}
