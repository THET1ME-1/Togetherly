import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:love_app/services/map/my_position_feed.dart';

/// Обращение 383 (TOG-9, iPhone): после «Выключить» на карте «Где мы» синяя
/// стрелка горела и вне приложения, пока Togetherly не смахнуть.
///
/// На iOS у geolocator ОДИН нативный поток на всё приложение: второй
/// `getPositionStream` получает тот же поток, а гаснет он, только когда
/// отпишутся все. Экран большой карты подписывался на него за своей точкой,
/// и эта подписка держала поток службы показа (с разрешённым фоном) после
/// «Выключить». Хуже того, подписка заводилась ПОСЛЕ первой точки: закрыл
/// экран раньше — и она оставалась навсегда.
Position _pos(double lat) => Position(
      latitude: lat,
      longitude: 28.8,
      timestamp: DateTime(2026, 10, 21),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  test('экран закрыли до первой точки — подписки на поток не остаётся',
      () async {
    final first = Completer<Position>();
    final stream = StreamController<Position>.broadcast();
    final got = <double>[];
    final feed = MyPositionFeed(
      onPosition: (p) => got.add(p.latitude),
      currentPosition: () => first.future,
      positionStream: () => stream.stream,
    );

    unawaited(feed.start());
    feed.dispose();
    first.complete(_pos(47));
    await Future<void>.delayed(Duration.zero);

    expect(stream.hasListener, isFalse,
        reason: 'подписка после закрытия держала бы нативный поток вечно');
    expect(got, isEmpty);
  });

  test('показ включён — карта берёт точку у службы и потока не трогает',
      () async {
    final shared = ValueNotifier<Position?>(_pos(46));
    var asked = 0;
    final got = <double>[];
    final feed = MyPositionFeed(
      onPosition: (p) => got.add(p.latitude),
      currentPosition: () async {
        asked++;
        return _pos(0);
      },
      positionStream: () {
        asked++;
        return const Stream<Position>.empty();
      },
      sharedFix: shared,
    );

    await feed.start();
    shared.value = _pos(47);
    expect(got, [46, 47]);
    expect(asked, 0,
        reason: 'вторая подписка на общий поток пережила бы «Выключить»');

    feed.dispose();
    shared.value = _pos(48);
    expect(got, [46, 47], reason: 'после закрытия экрана точки не нужны');
  });

  test('показ выключен — своя подписка, и закрытие экрана её снимает',
      () async {
    final stream = StreamController<Position>.broadcast();
    final got = <double>[];
    final feed = MyPositionFeed(
      onPosition: (p) => got.add(p.latitude),
      currentPosition: () async => _pos(46),
      positionStream: () => stream.stream,
    );

    await feed.start();
    stream.add(_pos(47));
    await Future<void>.delayed(Duration.zero);
    expect(got, [46, 47]);
    expect(stream.hasListener, isTrue);

    feed.dispose();
    expect(stream.hasListener, isFalse);
  });

  test('на поток геопозиции подписываются только служба показа и карта', () {
    // Разовая точка (getCurrentPosition) у плагина своя и потоку не мешает.
    const allowed = {
      'lib/services/live_location_service.dart',
      'lib/services/map/my_position_feed.dart',
    };
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !allowed.contains(f.path) &&
            f.readAsStringSync().contains('getPositionStream('))
          f.path,
    ];
    expect(offenders, isEmpty,
        reason: 'на iOS поток один на всё приложение: лишняя подписка держит '
            'его после «Выключить»');
  });
}
