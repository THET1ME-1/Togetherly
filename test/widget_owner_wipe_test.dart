// Данные виджетов не переходят к следующему человеку.
//
// Жалоба 14.08.2026: у человека два аккаунта Togetherly на одном телефоне. На
// аккаунте с Настей, которая ни одного фото не присылала, виджет показал фото
// Вики — из другого аккаунта и другой пары. Хранилище виджетов общее для
// устройства (HomeWidgetPreferences на Android, контейнер App Group на iOS), и
// данные прежнего владельца просто оставались лежать.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/home_widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ownerKey = 'widget_data_owner_uid';

  group('владелец данных виджетов', () {
    test('первый вход запоминает человека', () async {
      SharedPreferences.setMockInitialValues({});
      await HomeWidgetService.instance.ensureOwner('user-one');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ownerKey), 'user-one');
    });

    test('смена человека переписывает владельца', () async {
      SharedPreferences.setMockInitialValues({ownerKey: 'user-one'});
      await HomeWidgetService.instance.ensureOwner('user-two');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ownerKey), 'user-two');
    });

    test('пустой uid ничего не трогает', () async {
      SharedPreferences.setMockInitialValues({ownerKey: 'user-one'});
      await HomeWidgetService.instance.ensureOwner('');
      await HomeWidgetService.instance.ensureOwner(null);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ownerKey), 'user-one',
          reason: 'на старте сессия восстанавливается позже, это не выход');
    });

    test('выход забывает владельца', () async {
      SharedPreferences.setMockInitialValues({ownerKey: 'user-one'});
      await HomeWidgetService.instance.applyOwnerEvent('');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ownerKey), isNull,
          reason: 'иначе следующий вход тем же ключом сочтёт человека прежним');
    });
  });

  group('связка на месте', () {
    test('старт приложения привязывает виджеты к владельцу', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('HomeWidgetService.instance.ensureOwner'));
    });

    test('выход стирает данные виджетов', () {
      final auth = File('lib/services/pb_auth_service.dart').readAsStringSync();
      expect(auth, contains('wipeWidgetData'));
    });

    test('живой путь выхода тоже чистит', () {
      // Проверка выше смотрела на обёртку `PbAuthService.signOut`, а её из
      // приложения не зовут: выход идёт через `UserData.logout`, и виджеты
      // переживали его целиком (жалоба 18.08.2026).
      final userData = File('lib/models/user_data.dart').readAsStringSync();
      final logout = userData.substring(userData.indexOf('Future<void> logout()'));
      expect(logout.substring(0, 1200), contains('applyOwnerEvent'));
    });

    test('смена аккаунта ловится без перезапуска', () {
      // Одной проверки в `main()` мало: человек выходит и входит в другой
      // аккаунт, не убивая приложение.
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('watchOwner()'));
      final svc = File('lib/services/home_widget_service.dart').readAsStringSync();
      expect(svc, contains('authChanges.listen'));
    });

    test('Android умеет стирать', () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt',
      ).readAsStringSync();
      expect(kotlin, contains('"wipeWidgetData"'));
      // Стираются и значения, и привязки виджета к паре — они в одном хранилище.
      expect(kotlin, contains('HomeWidgetPreferences'));
    });

    test('iOS умеет стирать', () {
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(swift, contains('case "wipeWidgetData"'));
      // Картинки лежат отдельно от значений — убираем и их.
      expect(swift, contains('clearAppGroupMedia(prefix: "")'));
      expect(swift, contains('reloadAllTimelines'));
    });
  });
}
