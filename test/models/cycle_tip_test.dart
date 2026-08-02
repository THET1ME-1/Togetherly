import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/cycle_tip.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppStrings> stringsOf(AppLanguage lang) async {
    await LocaleService.instance.setLanguage(lang);
    return LocaleService.current;
  }

  test('семь советов на обоих языках, без пустых текстов', () async {
    for (final lang in AppLanguage.values) {
      final s = await stringsOf(lang);
      final tips = CycleTip.all(s);
      expect(tips.length, 7, reason: 'язык $lang');
      for (final t in tips) {
        expect(t.title.trim(), isNotEmpty, reason: 'язык $lang');
        expect(t.body.trim(), isNotEmpty, reason: 'язык $lang');
      }
    }
  });

  test('заголовки не повторяются', () async {
    final tips = CycleTip.all(await stringsOf(AppLanguage.ru));
    expect(tips.map((t) => t.title).toSet().length, tips.length);
  });

  test('совет про боль ведёт к врачу и не называет лекарств', () async {
    // Приложение не врач: конкретный препарат в подсказке становится чужой
    // ответственностью, а боль, которая валит с ног каждый цикл, требует осмотра.
    final tips = CycleTip.all(await stringsOf(AppLanguage.ru));
    final pain = tips.firstWhere((t) => t.title.toLowerCase().contains('боль'));
    expect(pain.body.toLowerCase(), contains('врач'));
    for (final drug in [
      'ибупрофен', 'но-шпа', 'нош-па', 'парацетамол', 'анальгин', 'аспирин',
    ]) {
      expect(pain.body.toLowerCase().contains(drug), isFalse,
          reason: 'в совете названо лекарство: $drug');
    }
  });
}
