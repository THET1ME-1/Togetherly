import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/live_location_tuning.dart';

/// Как часто приложение будит GPS, когда пара делится геопозицией.
///
/// Три жалобы за один день (21.08.2026): «на Айфоне постоянно отображается
/// значок геолокации, мешает и цепляет глаз», «на Андроиде постоянно висит
/// уведомление, что геопозиция включена», «после обновления постоянно
/// использует GPS». Метка партнёра при этом нужна — значит вопрос не в том,
/// выключить ли фон, а в том, как редко его будить.
void main() {
  group('на экране', () {
    final t = liveLocationTuning(foreground: true);

    test('точность высокая: человек смотрит на карту и ждёт свою метку', () {
      expect(t.highAccuracy, isTrue);
    });

    test('шаг мелкий — метка едет плавно', () {
      expect(t.distanceFilter, lessThanOrEqualTo(15));
    });
  });

  group('в фоне', () {
    final t = liveLocationTuning(foreground: false);

    test('шаг крупнее: дорога до работы не стоит сотни включений GPS', () {
      expect(t.distanceFilter, greaterThanOrEqualTo(50));
      expect(t.distanceFilter,
          greaterThan(liveLocationTuning(foreground: true).distanceFilter));
    });

    test('процессор не удерживаем: wake lock и есть «постоянный GPS»', () {
      expect(t.wakeLock, isFalse);
    });

    test('система вправе усыпить обновления, когда человек не двигается', () {
      expect(t.pauseAutomatically, isTrue);
    });

    test('синий индикатор не форсируем — его показывает сама система', () {
      expect(t.forceIndicator, isFalse);
    });
  });

  test('профиль меняется вместе с состоянием приложения', () {
    expect(liveLocationTuning(foreground: true),
        isNot(equals(liveLocationTuning(foreground: false))));
  });

  group('Android', () {
    final t = liveLocationTuning(foreground: true, android: true);

    test('профиль один на всё время: перезапуск потока показывает уведомление '
        'заново', () {
      expect(t, equals(liveLocationTuning(foreground: false, android: true)));
    });

    test('процессор не держим — на это и жалуются как на «постоянный GPS»', () {
      expect(t.wakeLock, isFalse);
    });

    test('шаг крупнее экранного, но точность спутниковая: метка нужна верная',
        () {
      expect(t.distanceFilter,
          greaterThan(liveLocationTuning(foreground: true).distanceFilter));
      expect(t.highAccuracy, isTrue);
    });
  });
}
