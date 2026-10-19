import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/user_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сезонная тема у человека: дата регистрации живёт на телефоне, а тема,
/// которую человек не застал, не красит приложение, даже если номер её
/// как-то оказался в настройках (перенос с другого устройства, старая копия).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => UserData.clock = DateTime.now);

  test('дата регистрации поднимается с телефона', () async {
    final registered = DateTime.utc(2026, 10, 30, 9);
    SharedPreferences.setMockInitialValues({
      'registeredAt': registered.millisecondsSinceEpoch,
    });
    final data = UserData();
    await data.loadFromPrefs();
    expect(data.registeredAt, registered);
  });

  test('не застал Хэллоуин — приложение в теме по умолчанию', () async {
    UserData.clock = () => DateTime.utc(2026, 11, 20);
    SharedPreferences.setMockInitialValues({
      'themeId': 25,
      'registeredAt': DateTime.utc(2026, 11, 3).millisecondsSinceEpoch,
    });
    final data = UserData();
    await data.loadFromPrefs();
    expect(data.themeId, 0);
    expect(data.hasTheme(25), isFalse);
  });

  test('застал — тема остаётся и после праздника', () async {
    UserData.clock = () => DateTime.utc(2026, 11, 20);
    SharedPreferences.setMockInitialValues({
      'themeId': 25,
      'registeredAt': DateTime.utc(2026, 10, 2).millisecondsSinceEpoch,
    });
    final data = UserData();
    await data.loadFromPrefs();
    expect(data.themeId, 25);
    expect(data.hasTheme(25), isTrue);
  });
}
