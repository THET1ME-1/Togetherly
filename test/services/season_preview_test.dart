import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/xmas_tree.dart';
import 'package:love_app/services/season_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Предпросмотр сезона: аккаунт из списка на сервере живёт в другом дне
/// (владелец 26.11.2026: «активируй новый год, только мне для теста»).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SeasonPreview.debugReset();
  });

  test('день из предпросмотра, время настоящее', () {
    final now = previewClock(DateTime(2026, 12, 1), DateTime(2026, 11, 26, 18, 42, 7));
    expect(now, DateTime(2026, 12, 1, 18, 42, 7));
  });

  test('каталог без предпросмотра — только включённое', () {
    expect(catalogFilter(const []), "enabled = true || kind = 'wear'");
  });

  test('каталог с предпросмотром — и спрятанные наборы сезона', () {
    expect(catalogFilter(const ['winter']), "enabled = true || kind = 'wear' || data.set = 'winter'");
    // чужое имя набора в запрос не попадает
    expect(catalogFilter(const ["x' || 1=1"]), "enabled = true || kind = 'wear'");
  });

  test('ответ сервера включает декабрь у ёлки, пустой — возвращает настоящий', () async {
    await SeasonPreview.apply({'ok': true, 'day': '2026-12-01', 'sets': ['winter']});
    expect(SeasonPreview.sets, ['winter']);
    expect(xtNow().month, 12);
    expect(xtActiveSeason(xtNow()), 2026);
    await SeasonPreview.apply({'ok': true, 'day': '', 'sets': []});
    expect(SeasonPreview.sets, isEmpty);
    expect(xtNow().day, DateTime.now().day);
  });

  test('смена дня будит экраны: главная перерисовывается без перезапуска', () async {
    var calls = 0;
    void hit() => calls++;
    SeasonPreview.changes.addListener(hit);
    addTearDown(() => SeasonPreview.changes.removeListener(hit));
    await SeasonPreview.apply({'ok': true, 'day': '2026-12-01', 'sets': ['winter']});
    expect(calls, 1);
    // тот же ответ ещё раз — будить незачем
    await SeasonPreview.apply({'ok': true, 'day': '2026-12-01', 'sets': ['winter']});
    expect(calls, 1);
    await SeasonPreview.apply({'ok': true, 'day': '', 'sets': []});
    expect(calls, 2);
  });

  test('день переживает перезапуск: читается из prefs до сети', () async {
    await SeasonPreview.apply({'ok': true, 'day': '2026-12-01', 'sets': ['winter']});
    SeasonPreview.debugReset();
    await SeasonPreview.loadSaved();
    expect(SeasonPreview.sets, ['winter']);
    expect(xtNow().month, 12);
  });
}
