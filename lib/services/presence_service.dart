import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';
import '../models/presence_liveness.dart';
import 'centrifugo_service.dart';
import 'pocketbase_service.dart';
import 'pb_data_service.dart';
import 'pb_realtime_service.dart';

/// «Мы оба тут» — через канал пары, а не через диск.
///
/// Как было до 14 августа 2026: каждый телефон обновлял `user_presence.seen_at`
/// раз в двенадцать секунд. При семистах активных это под шестьдесят записей в
/// секунду, а писатель у SQLite один — сохранение статуса, сообщения и
/// настроения вставали в очередь за чужими «я ещё тут». В ту ночь сервер на
/// этом и захлебнулся: запись висела по тридцать секунд, люди видели «сервер не
/// отвечает» и не могли войти.
///
/// Как стало: «я жив» летит публикацией в канал `pair:<группа>` и на диск не
/// попадает вовсе. В базу уходит редкая отметка раз в пять минут — только ради
/// подписи «была в 12:33» в шапке чата.
///
/// Партнёр со сборкой постарше про канал не знает и по-прежнему пишет отметки в
/// базу. Поэтому онлайн считается по двум источникам сразу: берём тот, что
/// свежее. Пока такие сборки живы, ничего не теряется.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();
  factory PresenceService() => instance;

  Timer? _heartbeat;
  bool _started = false;
  String _groupId = '';
  int? _lastStoredMs;

  /// Когда партнёров последний раз слышали по каналу: uid → миллисекунды.
  final Map<String, int> _beats = <String, int>{};

  /// Кому рассказать, что признак жизни обновился.
  final StreamController<String> _pulse = StreamController<String>.broadcast();

  RtUnsub? _unsub;

  String get _uid => PocketBaseService().userId ?? '';

  String _channel(String groupId) => 'pair:$groupId';

  /// Запустить (после входа и появления пары). Идемпотентно.
  ///
  /// Без [groupId] сервис работает по-старому — через отметки в базе: у
  /// одиночки канала пары нет.
  void start({String groupId = ''}) {
    if (_started && groupId == _groupId) return;
    if (_started) stop();
    _started = true;
    _groupId = groupId;
    WidgetsBinding.instance.addObserver(this);
    if (groupId.isNotEmpty) _listenChannel(groupId);
    _beat();
    _heartbeat = Timer.periodic(PresenceLiveness.beat, (_) => _beat());
  }

  void stop() {
    _started = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    _unsub?.call();
    _unsub = null;
    _beats.clear();
    _lastStoredMs = null;
    _groupId = '';
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> _listenChannel(String groupId) async {
    _unsub?.call();
    _unsub = await CentrifugoService().subscribeRaw(_channel(groupId), (data) {
      if (data['t'] != 'alive') return;
      final uid = (data['uid'] ?? '').toString();
      if (uid.isEmpty || uid == _uid) return;
      final at = data['at'];
      _beats[uid] = at is num
          ? at.toInt()
          : DateTime.now().millisecondsSinceEpoch;
      if (!_pulse.isClosed) _pulse.add(uid);
    });
  }

  void _beat() {
    final uid = _uid;
    if (uid.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_groupId.isNotEmpty) {
      // Публикация не касается диска: её видит только тот, кто сейчас в канале.
      CentrifugoService()
          .publish(_channel(_groupId), {'t': 'alive', 'uid': uid, 'at': now});
    }

    // Отметка «был в сети» нужна для подписи в шапке чата, и только для неё.
    if (PresenceLiveness.shouldWriteLastSeen(
        writtenAtMs: _lastStoredMs, nowMs: now)) {
      _lastStoredMs = now;
      PbDataService().touchPresence(uid);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    if (state == AppLifecycleState.resumed) {
      _beat();
      _heartbeat ??= Timer.periodic(PresenceLiveness.beat, (_) => _beat());
    } else {
      // Ушли в фон — перестаём подавать признаки жизни, и партнёр через
      // сорок пять секунд увидит офлайн.
      _heartbeat?.cancel();
      _heartbeat = null;
    }
  }

  /// Когда [uid] в последний раз был в сети — миллисекунды эпохи.
  ///
  /// Шапке чата нужен сам момент («была в 12:33»), поэтому смотрим и удары по
  /// каналу, и отметку в базе.
  Stream<int?> watchLastSeen(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _merged(uid).map((v) => v.$2);
  }

  /// В сети ли [uid] — живой поток.
  Stream<bool> watchOnline(String uid) {
    if (uid.isEmpty) return Stream.value(false);
    return _merged(uid).map((v) => v.$1).distinct();
  }

  /// Общий поток: (в сети, когда видели). Собирает канал, базу и часы.
  Stream<(bool, int?)> _merged(String uid) {
    late StreamController<(bool, int?)> ctrl;
    StreamSubscription<RecordModel?>? dbSub;
    StreamSubscription<String>? pulseSub;
    Timer? ticker;
    int? storedMs;

    void emit() {
      final now = DateTime.now().millisecondsSinceEpoch;
      final online = PresenceLiveness.isOnline(
        channelBeatMs: _beats[uid],
        storedSeenMs: storedMs,
        nowMs: now,
      );
      final seen = PresenceLiveness.lastSeenMs(
        channelBeatMs: _beats[uid],
        storedSeenMs: storedMs,
      );
      if (!ctrl.isClosed) ctrl.add((online, seen));
    }

    ctrl = StreamController<(bool, int?)>(
      onListen: () {
        // База: отметка партнёра приезжает редко, но она же держит совместимость
        // со сборками, которые про канал ещё не знают.
        dbSub = PbRealtimeService().watchPresence(uid).listen((rec) {
          storedMs = (rec?.data['seen_at'] as num?)?.toInt();
          emit();
        }, onError: (_) {});
        pulseSub = _pulse.stream.where((u) => u == uid).listen((_) => emit());
        // Часы: без них точка не погаснет, когда удары просто прекратились.
        ticker = Timer.periodic(const Duration(seconds: 10), (_) => emit());
        emit();
      },
      onCancel: () {
        dbSub?.cancel();
        pulseSub?.cancel();
        ticker?.cancel();
      },
    );
    return ctrl.stream;
  }
}
