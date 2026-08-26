import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/live_location_tuning.dart';

/// Как часто приложение будит GPS, когда пара делится геопозицией.
///
/// Двусторонний спор. Сначала три жалобы за день (21.08.2026): «на Айфоне
/// постоянно отображается значок геолокации, мешает и цепляет глаз», «на
/// Андроиде постоянно висит уведомление, что геопозиция включена», «после
/// обновления постоянно использует GPS». Экономию тогда взяли двумя мерами
/// разом — сняли wake lock и разрешили системе усыплять обновления, — и фон
/// умер: «геопозиция обновляется только при нахождении в приложении, даже
/// когда в настройках стоит „Всегда“, на iOS 26.6.1. В версии для Android
/// такая же проблема» (@melyron, 24.08.2026).
///
/// Отсюда правило: фон обязан доезжать до партнёра, а расход держат шаг,
/// точность и редкость опроса — не отключённый сон процессора.
void main() {
  group('на экране', () {
    final t = liveLocationTuning(foreground: true);

    test('точность высокая: человек смотрит на карту и ждёт свою метку', () {
      expect(t.highAccuracy, isTrue);
    });

    test('шаг мелкий — метка едет плавно', () {
      expect(t.distanceFilter, lessThanOrEqualTo(15));
    });

    test('опрос частый: карта открыта, метка не должна стоять', () {
      expect(t.interval, lessThanOrEqualTo(const Duration(seconds: 15)));
    });
  });

  group('в фоне', () {
    final t = liveLocationTuning(foreground: false);

    test('шаг крупнее: дорога до работы не стоит сотни включений GPS', () {
      expect(t.distanceFilter, greaterThanOrEqualTo(50));
      expect(t.distanceFilter,
          greaterThan(liveLocationTuning(foreground: true).distanceFilter));
    });

    test('система НЕ вправе усыплять обновления: из этого сна их будит только '
        'открытое приложение — метка партнёра замирала', () {
      expect(t.pauseAutomatically, isFalse);
    });

    test('опрос редкий — это и есть экономия вместо остановки фона', () {
      expect(t.interval, greaterThanOrEqualTo(const Duration(seconds: 30)));
    });

    test('синий индикатор в фоне форсируем — иначе ревью не видит фичи', () {
      // App Review отклонил 1.31.0 по 2.5.4 (заявка b7ab1101, 26.08.2026):
      // режим `location` объявлен, а признаков персистентной геолокации
      // ревьюер не нашёл. Стрелка — единственное, что он вообще видит: карта
      // «Где мы» рисуется только у пары, а шаринг выключен по умолчанию. В
      // принятых 1.29.5–1.30.0 она горела.
      expect(t.forceIndicator, isTrue);
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

    test('процессор держим разбуженным: без wake lock foreground-сервис живёт, '
        'а координаты в фоне не приходят', () {
      expect(t.wakeLock, isTrue);
    });

    test('расход гасит редкий опрос, а не остановленный фон', () {
      expect(t.interval, greaterThanOrEqualTo(const Duration(seconds: 45)));
    });

    test('шаг крупнее экранного, но точность спутниковая: метка нужна верная',
        () {
      expect(t.distanceFilter,
          greaterThan(liveLocationTuning(foreground: true).distanceFilter));
      expect(t.highAccuracy, isTrue);
    });
  });
}
