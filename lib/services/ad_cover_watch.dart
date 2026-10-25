import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/ad_cover.dart';

/// Канал `love_app/ad_cover`: натив описывает стопку контроллеров над
/// Flutter (`state`) и убирает пустой прозрачный слой плагина рекламы
/// (`dismissLeftover`). Ответ — `AppDelegate.setupAdCoverChannel`.
const String adCoverChannelName = 'love_app/ad_cover';

/// Наблюдатель за полноэкранной рекламой на iPhone (TOG-37): пока идёт
/// показ, раз в [every] спрашивает натив о стопке контроллеров и замечает,
/// что ролик ушёл, даже когда событие «закрыто» от Яндекса потерялось.
///
/// На других платформах и со старым нативом, где канала нет, молчит: показ
/// идёт как раньше, по событиям SDK и жизненному циклу.
class AdCoverWatch {
  AdCoverWatch({
    MethodChannel channel = const MethodChannel(adCoverChannelName),
    this.every = const Duration(milliseconds: 400),
    this.leftoverGrace = const Duration(seconds: 1),
    bool? enabled,
  }) : _channel = channel,
       _enabled = enabled ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final MethodChannel _channel;
  final bool _enabled;

  /// Как часто спрашивать натив.
  final Duration every;

  /// Сколько ждать, прежде чем убрать оставшийся слой плагина: событие
  /// «закрыто» может прийти с опозданием, и тогда плагин уберёт его сам.
  final Duration leftoverGrace;

  final AdCoverTracker _tracker = AdCoverTracker();
  final Completer<void> _closed = Completer<void>();
  Timer? _timer;
  bool _asking = false;
  bool _stopped = false;

  /// Ролик был виден в стопке: показ состоялся, даже без `onAdShown`.
  bool get sawAd => _tracker.sawAd;

  /// Ролик, который был виден, ушёл из стопки.
  Future<void> get closed => _closed.future;

  void start() {
    if (!_enabled || _timer != null || _stopped) return;
    _timer = Timer.periodic(every, (_) => _ask());
  }

  /// Опрос кончается. Уборка оставшегося слоя, если уже назначена, доходит:
  /// без неё касания так и уходили бы в прозрачный контроллер плагина.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _ask() async {
    if (_asking || _stopped) return;
    _asking = true;
    try {
      final raw = await _channel.invokeMethod<Object?>('state');
      if (_stopped) return;
      _tracker.onSnapshot(AdCoverSnapshot.fromMap(raw));
      if (_tracker.closed && !_closed.isCompleted) {
        _closed.complete();
        if (_tracker.leftover) unawaited(_dropLeftover());
        stop();
      }
    } on MissingPluginException {
      // Сборка, у которой натив канала ещё не знает.
      stop();
    } on PlatformException catch (e) {
      debugPrint('ad_cover: натив ответил ошибкой — ${e.code}');
      stop();
    } finally {
      _asking = false;
    }
  }

  Future<void> _dropLeftover() async {
    await Future<void>.delayed(leftoverGrace);
    try {
      // Натив сам проверит, что слой по-прежнему пуст и висит сверху.
      final dropped = await _channel.invokeMethod<bool>('dismissLeftover');
      if (dropped == true) debugPrint('ad_cover: убран пустой слой плагина рекламы');
    } on MissingPluginException {
      // Старый натив: убрать нечем.
    } on PlatformException catch (e) {
      debugPrint('ad_cover: слой не убран — ${e.code}');
    }
  }
}
