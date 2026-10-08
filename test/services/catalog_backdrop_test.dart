import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/catalog_service.dart';

/// Сезонный фон приходит записью каталога вида `backdrop`, как сундук: новый
/// сезон — новая запись, без релиза.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('каталог отдаёт фон, который идёт сегодня', () {
    CatalogService.instance.debugApply([
      {
        'id': 'backdrop_hw',
        'kind': 'backdrop',
        'data': {
          'key': 'hw',
          'from': '2026-10-08',
          'until': '2026-11-01',
          'files': {'mask': 'https://x/mask.webp'},
        },
      },
      {'id': 'backdrop_bad', 'kind': 'backdrop', 'data': {'key': 'bad'}},
    ]);
    expect(CatalogService.instance.backdrops.map((b) => b.key), ['hw']);
    expect(CatalogService.instance.activeBackdrop(DateTime(2026, 10, 20))?.key, 'hw');
    expect(CatalogService.instance.activeBackdrop(DateTime(2026, 11, 2)), isNull);
  });

  test('запись выключили на сервере — фона нет', () {
    CatalogService.instance.debugApply(const []);
    expect(CatalogService.instance.activeBackdrop(DateTime(2026, 10, 20)), isNull);
  });
}
