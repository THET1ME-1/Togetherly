import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/lang_tag.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Пуши пишет сервер, и он должен знать язык человека: без этого уведомления
/// уходили всем по-русски (отзыв в App Store 19.08.2026).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> written;
  late String? stored;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.en);
    written = [];
    stored = null;
    LangTag.debugReset(
      read: () => stored,
      write: (code) async {
        written.add(code);
        stored = code;
      },
    );
  });

  tearDown(LangTag.stop);

  test('при запуске пишет язык приложения', () async {
    await LangTag.start();
    expect(written, ['en']);
  });

  test('тот же язык уже в профиле — запроса нет', () async {
    stored = 'en';
    await LangTag.start();
    expect(written, isEmpty);
  });

  test('сменили язык — сервер узнаёт новый', () async {
    await LangTag.start();
    await LocaleService.instance.setLanguage(AppLanguage.uk);
    await pumpEventQueue();
    expect(written, ['en', 'uk']);
  });
}
