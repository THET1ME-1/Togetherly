import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Подарки зимнего сундука (27.11.2026) приходят из каталога с названием на
/// русском и английском; остальные семь языков берутся из таблиц подарков
/// приложения. Без них португалец видел бы «Mistletoe».
void main() {
  const keys = ['ng_cracker', 'ng_mistletoe', 'ng_jar', 'ng_skates', 'ng_window', 'ng_angels', 'ng_igloo'];
  const ru = ['Хлопушка', 'Омела', 'Банка огоньков', 'Коньки на одном шнурке', 'Ладошки на окне', 'Снежные ангелы', 'Иглу на двоих'];
  const en = ['Party cracker', 'Mistletoe', 'Jar of lights', 'Skates on one lace', 'Hands on the window', 'Snow angels', 'Igloo for two'];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GiftCatalog.registerSeasonal({
      for (var i = 0; i < keys.length; i++)
        keys[i]: Gift(key: keys[i], price: 0, engine: GiftEngine.response, titleRu: ru[i], titleEn: en[i]),
    });
  });

  for (final lang in [AppLanguage.pt, AppLanguage.de, AppLanguage.fr, AppLanguage.es, AppLanguage.it, AppLanguage.zh, AppLanguage.uk]) {
    test('зимние подарки названы на языке ${lang.code}', () async {
      await LocaleService.instance.setLanguage(lang);
      for (var i = 0; i < keys.length; i++) {
        final t = GiftCatalog.byKey(keys[i])!.title;
        expect(t, isNot(en[i]), reason: '${keys[i]} на ${lang.code} — английское');
        expect(t.trim(), isNotEmpty);
      }
    });
  }
}
