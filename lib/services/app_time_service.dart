import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_time_counter.dart';
import '../models/rank.dart';
import 'pocketbase_service.dart';

typedef AppTimeSend =
    Future<Map<String, dynamic>?> Function(
      String path,
      Map<String, dynamic> body,
    );

/// Часы в приложении для званий (05.11.2026, план 2026-11-05-ranks-by-hours).
///
/// Считает время, пока приложение на экране (`AppTimeCounter`), раз в 5 минут
/// и при сворачивании отправляет секунды в hotpath (`/api/user/app-time`).
/// Сервер — источник правды: он засчитывает не больше реального времени.
/// Несданное лежит в настройках и переживает перезапуск.
class AppTimeService with WidgetsBindingObserver {
  AppTimeService._();
  static final AppTimeService instance = AppTimeService._();

  @visibleForTesting
  AppTimeService.forTest();

  static const _kPending = 'app_time_pending';
  static const _kDevice = 'app_time_device';
  static const _kServer = 'app_time_seconds';
  static const _kSeen = 'app_time_rank_seen';
  static const _tickEvery = Duration(seconds: 15);
  static const _flushEvery = Duration(minutes: 5);

  /// Не принятое сервером сверх часа не копим: значит, его и не было.
  static const _keepMax = 3600;

  final AppTimeCounter counter = AppTimeCounter();

  /// Часы человека: принятые сервером плюс насчитанные здесь и не отправленные.
  final ValueNotifier<int> seconds = ValueNotifier(0);

  /// Последнее звание, чей экран человек уже видел (-1 — никакого).
  int rankSeen = -1;

  /// Сервер ответил хотя бы раз за этот запуск: до этого `rankSeen` может быть
  /// старым (переустановка, второй телефон) и экран звания не показывается.
  bool synced = false;

  /// Пороги званий из `app_config.rank_hours`.
  List<num> hours = kRankHours;

  @visibleForTesting
  AppTimeSend send = _send;
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  bool _started = false;
  bool _flushing = false;
  String _device = '';
  int _server = 0;
  Timer? _tick;
  Timer? _flushTimer;

  /// Поле `rank_hours` из записи `app_config`; null известное не трогает.
  void ingestHours(Object? raw) {
    if (raw == null) return;
    hours = parseRankHours(raw);
    _publish();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final p = await SharedPreferences.getInstance();
    _device = p.getString(_kDevice) ?? '';
    if (_device.isEmpty) {
      final r = Random.secure();
      _device = List.generate(
        16,
        (_) => r.nextInt(16).toRadixString(16),
      ).join();
      await p.setString(_kDevice, _device);
    }
    counter.restore(p.getInt(_kPending) ?? 0);
    _server = p.getInt(_kServer) ?? 0;
    rankSeen = p.getInt(_kSeen) ?? -1;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    final state = binding.lifecycleState;
    counter.screen(state == null || state == AppLifecycleState.resumed, now());
    _tick = Timer.periodic(_tickEvery, (_) {
      counter.tick(now());
      _publish();
      unawaited(_save());
    });
    _flushTimer = Timer.periodic(_flushEvery, (_) => flush());
    _publish();
    unawaited(flush());
  }

  @visibleForTesting
  void stop() {
    _tick?.cancel();
    _flushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final on = state == AppLifecycleState.resumed;
    counter.screen(on, now());
    _publish();
    if (!on) {
      unawaited(_save());
      unawaited(flush());
    }
  }

  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) counter.touch(now());
  }

  /// Отправить насчитанное. Сбой сети ничего не теряет: секунды ждут следующей
  /// попытки в настройках.
  Future<void> flush() async {
    if (_flushing || _device.isEmpty) return;
    _flushing = true;
    try {
      counter.tick(now());
      final res = await send('/api/user/app-time', {
        'device': _device,
        'seconds': counter.pendingSeconds,
      });
      if (res == null || res['ok'] != true) return;
      counter.sent((res['granted'] as num?)?.toInt() ?? 0);
      final extra = counter.pendingSeconds - _keepMax;
      if (extra > 0) counter.sent(extra);
      _server = (res['seconds'] as num?)?.toInt() ?? _server;
      rankSeen = max(rankSeen, (res['rank_seen'] as num?)?.toInt() ?? -1);
      synced = true;
      await _save();
    } catch (e) {
      debugPrint('AppTime.flush: $e');
    } finally {
      _flushing = false;
      _publish();
    }
  }

  /// Экран нового звания показан: больше его не показывать, и на другом
  /// телефоне тоже.
  Future<void> markSeen(int rank) async {
    if (rank <= rankSeen) return;
    rankSeen = rank;
    await _save();
    try {
      await send('/api/user/app-time/seen', {'rank': rank});
    } catch (e) {
      debugPrint('AppTime.markSeen: $e');
    }
  }

  void _publish() => seconds.value = _server + counter.pendingSeconds;

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kPending, counter.pendingSeconds);
      await p.setInt(_kServer, _server);
      await p.setInt(_kSeen, rankSeen);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _send(
    String path,
    Map<String, dynamic> body,
  ) async {
    final pb = PocketBaseService().pb;
    if (!pb.authStore.isValid) return null;
    final res = await pb
        .send(path, method: 'POST', body: body)
        .timeout(const Duration(seconds: 15));
    return res is Map ? res.cast<String, dynamic>() : null;
  }
}
