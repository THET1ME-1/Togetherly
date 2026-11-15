import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:love_app/models/fgs_start_allowed.dart';

/// Можно ли поднимать location-сервис прямо сейчас.
///
/// Android 12+ запрещает старт foreground-сервиса типа location из фона и
/// роняет `ForegroundServiceStartNotAllowedException` — исключение летит мимо
/// try/catch и мимо onError потока, поэтому единственная защита — не звать.
/// За неделю так упало у 49 человек.
void main() {
  group('fgsLocationStartAllowed', () {
    test('на переднем плане поднимать можно', () {
      expect(
        fgsLocationStartAllowed(AppLifecycleState.resumed, android: true),
        isTrue,
      );
    });

    test('из фона нельзя', () {
      expect(
        fgsLocationStartAllowed(AppLifecycleState.paused, android: true),
        isFalse,
      );
      expect(
        fgsLocationStartAllowed(AppLifecycleState.hidden, android: true),
        isFalse,
      );
      expect(
        fgsLocationStartAllowed(AppLifecycleState.detached, android: true),
        isFalse,
      );
    });

    test('состояние неизвестно — на Android считаем фоном', () {
      // Ровно так выглядит холодный старт из фонового пробуждения: тихий пуш,
      // WorkManager, обновление виджета. Раньше `null` считался передним
      // планом, и сервис падал при первом же таком запуске.
      expect(fgsLocationStartAllowed(null, android: true), isFalse);
    });

    test('шторка уведомлений уходом не считается', () {
      // inactive даёт входящий звонок и шторка: приложение всё ещё на экране.
      expect(
        fgsLocationStartAllowed(AppLifecycleState.inactive, android: true),
        isTrue,
      );
    });

    test('на iPhone ограничения нет — там фон разрешён режимом Info.plist', () {
      expect(fgsLocationStartAllowed(null, android: false), isTrue);
      expect(
        fgsLocationStartAllowed(AppLifecycleState.paused, android: false),
        isTrue,
      );
    });
  });

  group('locationPermissionGranted', () {
    // Bugsink, 1.43: «Starting FGS with type location … requires permissions»
    // — «Где мы» включали раньше, а разрешение потом отозвали.
    test('без разрешения службу не поднимаем', () {
      expect(locationPermissionGranted(LocationPermission.denied), isFalse);
      expect(locationPermissionGranted(LocationPermission.deniedForever), isFalse);
      expect(locationPermissionGranted(LocationPermission.unableToDetermine), isFalse);
    });

    test('«всегда» и «при использовании» годятся', () {
      expect(locationPermissionGranted(LocationPermission.always), isTrue);
      expect(locationPermissionGranted(LocationPermission.whileInUse), isTrue);
    });
  });

  test('старт потока проверяет разрешение, а не только передний план', () {
    final src = File('lib/services/live_location_service.dart').readAsStringSync();
    final start = src.indexOf('Future<void> startSharing(');
    final stream = src.indexOf('getPositionStream(', start);
    final check = src.indexOf('_hasLocationPermission()', start);
    expect(check, greaterThan(start));
    expect(check, lessThan(stream), reason: 'проверка разрешения обязана стоять до запуска потока');
  });
}
