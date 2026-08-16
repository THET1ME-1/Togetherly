import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/user_data.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Новый человек начинает со светлой розовой темы, а не с системной.
///
/// Системный режим отдавал приложение чужому решению: у половины телефонов
/// включена ночная тема, и первое, что видел человек, — тёмный экран, хотя
/// приложение задумано светлым и розовым. Выбор остаётся за человеком, но
/// начинается с нашего.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('по умолчанию — светлый режим', () async {
    SharedPreferences.setMockInitialValues({});
    final data = UserData();
    await data.loadFromPrefs();

    expect(data.themeMode, AppThemeMode.light);
  });

  test('акцент по умолчанию — розовый', () async {
    SharedPreferences.setMockInitialValues({});
    final data = UserData();
    await data.loadFromPrefs();

    expect(data.themeId, 0, reason: 'нулевая палитра — розовая');
  });

  test('свой выбор не перебиваем', () async {
    SharedPreferences.setMockInitialValues({
      'themeMode': AppThemeMode.dark.index,
      'themeId': 7,
    });
    final data = UserData();
    await data.loadFromPrefs();

    expect(data.themeMode, AppThemeMode.dark);
    expect(data.themeId, 7);
  });

  test('кто сидел на старой тёмной палитре, остаётся в тёмном', () async {
    // Миграция «акцент × режим»: индексы 20–24 были тёмными темами.
    SharedPreferences.setMockInitialValues({'themeId': 21});
    final data = UserData();
    await data.loadFromPrefs();

    expect(data.themeMode, AppThemeMode.dark);
  });
}
