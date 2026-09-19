import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:love_app/services/map/directions.dart';

void main() {
  const to = LatLng(55.752, 37.6175);

  test('Android отдаёт системе geo: — приложение карт выбирает телефон', () {
    final uri = androidGeoUri(to, 'Аня');
    expect(uri.scheme, 'geo');
    expect(uri.toString(), startsWith('geo:55.752,37.6175?q=55.752,37.6175('));
    expect(Uri.decodeComponent(uri.toString()), contains('(Аня)'));
  });

  test('без имени метки нет, только точка', () {
    expect(androidGeoUri(to, '  ').toString(), 'geo:55.752,37.6175?q=55.752,37.6175');
  });

  test('на iPhone Apple Карты идут первыми и открываются всегда', () {
    final apps = iosMapApps(to);
    expect(apps.first.uri.host, 'maps.apple.com');
    expect(apps.map((a) => a.uri.scheme).toSet(), containsAll(['https', 'comgooglemaps', 'yandexmaps', 'dgis']));
  });

  test('2ГИС ждёт долготу первой', () {
    final dgis = iosMapApps(to).firstWhere((a) => a.uri.scheme == 'dgis');
    expect(dgis.uri.toString(), endsWith('/to/37.6175,55.752'));
  });
}
