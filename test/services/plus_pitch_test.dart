import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/ui_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Рассказ про Togetherly+ показывается один раз после обновления. Сломается
/// эта проверка — и экран с ценой начнёт вылезать на каждый запуск; это тот
/// самый случай, когда «мелкая» ошибка выглядит как навязчивая реклама.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Показ рассказа про Плюс', () {
    test('На новой версии показываем один раз', () async {
      expect(await UiPrefs.plusPitchShownFor('1.20.0+147'), isFalse);
      await UiPrefs.markPlusPitchShown('1.20.0+147');
      expect(await UiPrefs.plusPitchShownFor('1.20.0+147'), isTrue);
    });

    test('Следующее обновление снова показывает', () async {
      await UiPrefs.markPlusPitchShown('1.20.0+147');
      expect(await UiPrefs.plusPitchShownFor('1.21.0+150'), isFalse);
    });

    test('Сборка того же имени, но другого номера — это другая версия', () async {
      await UiPrefs.markPlusPitchShown('1.20.0+147');
      expect(await UiPrefs.plusPitchShownFor('1.20.0+148'), isFalse);
    });
  });

  group('Первый запуск', () {
    test('Чистая установка — рассказ пропускаем', () async {
      expect(await UiPrefs.isFirstLaunchEver(), isTrue);
    });

    test('Экран приглашения уже видели — значит запуск не первый', () async {
      await UiPrefs.markInviteScreenShown();
      expect(await UiPrefs.isFirstLaunchEver(), isFalse);
    });

    test('Рассказ уже показывали — значит запуск не первый', () async {
      await UiPrefs.markPlusPitchShown('1.19.0+145');
      expect(await UiPrefs.isFirstLaunchEver(), isFalse);
    });
  });
}
