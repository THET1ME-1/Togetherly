import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Заставка при запуске приходит записью каталога вида `splash`: новая
/// заставка — новая запись, без релиза.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, dynamic> row(String key, {String until = '2026-11-01', int sort = 100}) => {
        'id': 'splash_$key',
        'kind': 'splash',
        'data': {
          'key': key,
          'ms': 1800,
          'step': 20,
          'until': until,
          'sort': sort,
          'window': {
            'path': 'M0,19 C-10,10 -20,0 -18,-10 C-14,-18 -4,-16 0,-10 Z',
            'track': [
              [180, 372, 0],
            ],
          },
          'sprites': {
            'door': {
              'frames': ['door'],
              'box': [0, 0, 360, 780],
            },
          },
          'layers': [
            {'sprite': 'door', 'fill': true, 'under': true},
          ],
          'files': {'door': 'https://x/door.webp', 'still': 'https://x/still.webp'},
        },
      };

  test('каталог отдаёт заставки, что идут сегодня, по порядку', () {
    CatalogService.instance.debugApply([
      row('hw_key', sort: 200),
      row('spring', sort: 50, until: '2026-06-01'),
      row('love', sort: 100, until: ''),
      {'id': 'splash_bad', 'kind': 'splash', 'data': {'key': 'bad'}},
    ]);
    expect(CatalogService.instance.splashesOn(DateTime(2026, 10, 20)).map((s) => s.key), ['love', 'hw_key']);
    expect(CatalogService.instance.splashesOn(DateTime(2026, 11, 2)).map((s) => s.key), ['love']);
  });

  test('запись сняли с сервера — заставки в выборе нет', () {
    CatalogService.instance.debugApply(const []);
    expect(CatalogService.instance.splashesOn(DateTime(2026, 10, 20)), isEmpty);
  });
}
