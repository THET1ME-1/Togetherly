import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Своя точка для экрана большой карты.
///
/// На iOS у geolocator один нативный поток на всё приложение: повторный
/// `getPositionStream` отдаёт тот же поток с настройками первого, а гаснет он,
/// только когда отпишутся все. Поэтому, пока показ геопозиции включён, карта
/// берёт точку у [LiveLocationService] ([sharedFix]) и на поток не
/// подписывается: иначе её подписка держала бы фоновый поток службы после
/// «Выключить» (обращение 383). Без показа карта заводит свою подписку, и
/// только если экран к тому моменту не закрыли.
class MyPositionFeed {
  MyPositionFeed({
    required this.onPosition,
    Future<Position> Function()? currentPosition,
    Stream<Position> Function()? positionStream,
    this.sharedFix,
  })  : _currentPosition = currentPosition ?? _firstFix,
        _positionStream = positionStream ?? _stream;

  final void Function(Position position) onPosition;
  final Future<Position> Function() _currentPosition;
  final Stream<Position> Function() _positionStream;

  /// Последняя точка службы показа, если её поток сейчас идёт.
  final ValueListenable<Position?>? sharedFix;

  StreamSubscription<Position>? _sub;
  bool _closed = false;

  static Future<Position> _firstFix() => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

  static Stream<Position> _stream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );

  Future<void> start() async {
    final shared = sharedFix;
    if (shared != null) {
      shared.addListener(_onShared);
      _onShared();
      return;
    }
    try {
      final pos = await _currentPosition();
      if (_closed) return;
      onPosition(pos);
    } catch (_) {}
    if (_closed) return;
    _sub = _positionStream().listen(onPosition, onError: (_) {});
  }

  void _onShared() {
    final pos = sharedFix?.value;
    if (pos != null && !_closed) onPosition(pos);
  }

  void dispose() {
    _closed = true;
    sharedFix?.removeListener(_onShared);
    _sub?.cancel();
    _sub = null;
  }
}
