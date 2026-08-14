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
      expect(prefs.getString(ownerKey), 'user-one');
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
