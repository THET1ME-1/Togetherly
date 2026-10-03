import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// geolocator_android до 5.0.2 после неудачной проверки настроек геолокации
/// всё равно звал `getResult()`. На прошивках без настоящих сервисов Google
/// (AOSP, microG) это `RuntimeExecutionException: LocationServices.API is not
/// available` в главном потоке, и приложение вылетает целиком: обращение 225,
/// Poco F3 на AOSP, «куда ни нажмёшь — вылетает» (03.10.2026).
void main() {
  test('geolocator_android не старее 5.0.2', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final m = RegExp(
      r'\n  geolocator_android:\n(?:    .*\n)*?    version: "(\d+)\.(\d+)\.(\d+)',
    ).firstMatch(lock);
    expect(m, isNotNull, reason: 'geolocator_android нет в pubspec.lock');
    final v = [for (var i = 1; i <= 3; i++) int.parse(m!.group(i)!)];
    final fresh = v[0] > 5 || (v[0] == 5 && (v[1] > 0 || v[2] >= 2));
    expect(fresh, isTrue, reason: 'стоит ${v.join('.')}');
    // С 5.0.3 плагин требует Android Gradle Plugin 9, проект на 8.11.
    expect(v, [5, 0, 2],
        reason: 'выше 5.0.2 только вместе с переходом проекта на AGP 9');
  });
}
