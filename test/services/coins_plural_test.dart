import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Числительные при монетах: до 28 июля на каждой награде висело «+1 монет».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  test('Русские окончания у монет', () {
    final s = LocaleService.current;
    expect(s.coinsPlus(1), '+1 монета');
    expect(s.coinsPlus(2), '+2 монеты');
    expect(s.coinsPlus(4), '+4 монеты');
    expect(s.coinsPlus(5), '+5 монет');
    expect(s.coinsPlus(11), '+11 монет', reason: 'одиннадцать — исключение');
    expect(s.coinsPlus(14), '+14 монет');
    expect(s.coinsPlus(21), '+21 монета');
    expect(s.coinsPlus(102), '+102 монеты');
    expect(s.coinsPlus(150), '+150 монет');
  });
}
