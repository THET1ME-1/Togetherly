import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож фоновой геолокации на iPhone.
///
/// `geolocator` включает фоновые обновления только тогда, когда в
/// `UIBackgroundModes` объявлен режим `location`
/// (`GeolocationHandler.m`: `shouldEnableBackgroundLocationUpdates`). Без него
/// наш `allowBackgroundLocationUpdates: true` гасится МОЛЧА: ни исключения, ни
/// строки в Bugsink — просто метка партнёра замирает в секунду, когда он ушёл
/// с экрана. Замер по проду 18.08.2026: у iOS точка новее последнего визита
/// только у 3% пар против 37% у Android.
///
/// Разрешение тоже проверяем: без строки `NSLocationAlwaysAndWhenInUseUsage
/// Description` система не покажет запрос «Разрешить всегда», и фон опять не
/// заработает — теперь уже по вине разрешения.
void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final service = File('lib/services/live_location_service.dart').readAsStringSync();

  /// Значения массива `<key>имя</key><array>…</array>`.
  List<String> arrayOf(String key) {
    final m = RegExp('<key>$key</key>\\s*<array>(.*?)</array>', dotAll: true)
        .firstMatch(plist);
    if (m == null) return const [];
    return RegExp(r'<string>(.*?)</string>')
        .allMatches(m.group(1)!)
        .map((e) => e.group(1)!)
        .toList();
  }

  String valueOf(String key) {
    final m = RegExp('<key>$key</key>\\s*<string>(.*?)</string>', dotAll: true)
        .firstMatch(plist);
    return m?.group(1) ?? '';
  }

  test('код просит фоновую геолокацию — значит режим location объявлен', () {
    final asksForBackground =
        RegExp(r'allowBackgroundLocationUpdates:\s*true').hasMatch(service);
    if (!asksForBackground) return; // фон выключили осознанно — проверять нечего
    expect(
      arrayOf('UIBackgroundModes'),
      contains('location'),
      reason: 'без location в UIBackgroundModes geolocator гасит фон молча',
    );
  });

  test('запрос «Разрешить всегда» объяснён человеку', () {
    final always = valueOf('NSLocationAlwaysAndWhenInUseUsageDescription');
    expect(always, isNotEmpty);
    // Текст читает и человек, и ревьюер Apple: он обязан говорить про карту с
    // партнёром и про закрытое приложение, а не про «воспоминания с местом».
    final low = always.toLowerCase();
    expect(
      low.contains('partner') || low.contains('map'),
      isTrue,
      reason: 'строка обязана называть, ради чего фон: карта с партнёром',
    );
    expect(valueOf('NSLocationWhenInUseUsageDescription'), isNotEmpty);
  });
}
