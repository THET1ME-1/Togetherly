import 'dart:async';

import 'package:flutter/widgets.dart';

import 'pocketbase_service.dart';

/// Попадание, которое сейчас показывается: сколько снежков и от кого.
/// [serial] растёт с каждым новым показом; серия, пришедшая во время показа,
/// только прибавляет [count] и номер не меняет.
@immutable
class SnowHit {
  const SnowHit(this.serial, this.count, this.from);
  final int serial;
  final int count;
  final String from;
}

/// Снежки темы «Новый год» (27.11.2026).
///
/// Бросок уходит на сервер (`POST /api/group/snowball`), тот кладёт его в
/// канал пары и шлёт пуш тому, кто не в приложении. У партнёра попадание
/// показывает [SnowHitOverlay] по [current]: событие канала пары
/// ([PbPushService]) или непросмотренные снежки при входе ([checkPending]).
class SnowballService with WidgetsBindingObserver {
  SnowballService._();
  static final SnowballService instance = SnowballService._();
  bool _observing = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись из фона (часто — по пушу «В тебя прилетел снежок»).
    if (state == AppLifecycleState.resumed) unawaited(checkPending());
  }

  /// Попадание на экране; null — снега нет.
  final ValueNotifier<SnowHit?> current = ValueNotifier<SnowHit?>(null);

  String _group = '';
  String _partner = '';
  DateTime? _lastThrow;
  int _serial = 0;

  /// Текущая пара и имя партнёра (для плашки «Снежок от …»). Новая пара —
  /// сразу спросить, не прилетело ли что-то, пока приложение было закрыто.
  void bind(String groupId, String partnerName) {
    final changed = groupId != _group;
    _group = groupId;
    _partner = partnerName;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    if (changed) unawaited(checkPending());
  }

  /// Бросить снежок партнёру. Зажатый палец не шлёт десяток: не чаще раза в
  /// 2 с (сервер держит тот же предел). Без пары — ничего.
  Future<void> throwBall(String groupId) async {
    if (groupId.isEmpty || groupId == 'solo') return;
    final now = DateTime.now();
    if (_lastThrow != null && now.difference(_lastThrow!) < const Duration(seconds: 2)) return;
    _lastThrow = now;
    try {
      await PocketBaseService().pb.send('/api/group/snowball', method: 'POST', body: {'groupId': groupId});
    } catch (e) {
      debugPrint('SnowballService.throwBall: $e');
    }
  }

  /// Бросить в ответ из плашки попадания — в текущую пару.
  Future<void> throwBack() => throwBall(_group);

  /// Прилетело [n] снежков. Во время показа серия прибавляется к числу на
  /// плашке, а не встаёт в очередь из десяти анимаций.
  void hit(int n, {String? partnerName}) {
    if (n <= 0) return;
    final from = (partnerName ?? _partner);
    final cur = current.value;
    current.value = cur == null ? SnowHit(++_serial, n, from) : SnowHit(cur.serial, cur.count + n, cur.from);
  }

  final Set<String> _received = {};

  /// Снежок [id] долетел вживую (канал пары): попадание и подтверждение
  /// серверу, чтобы при следующем открытии он не прилетел второй раз. Один
  /// номер — одно попадание, даже если событие пришло дважды.
  void received(String id) {
    if (id.isEmpty || !_received.add(id)) return;
    hit(1);
    final g = _group;
    if (g.isNotEmpty) unawaited(_ack(id, g));
  }

  Future<void> _ack(String id, String group) async {
    try {
      await (debugAck ?? (id) => PocketBaseService().pb.send('/api/group/snowball', method: 'POST', body: {'groupId': group, 'seen': id}))(id);
    } catch (e) {
      debugPrint('SnowballService.ack: $e');
    }
  }

  @visibleForTesting
  Future<void> Function(String id)? debugAck;

  @visibleForTesting
  void bindForTest(String groupId, String partnerName) {
    _group = groupId;
    _partner = partnerName;
  }

  /// Показ [hit] закончился. Новое попадание, начатое тем временем, не трогаем.
  void done(SnowHit hit) {
    if (current.value?.serial == hit.serial) current.value = null;
  }

  /// Снежки, прилетевшие, пока приложение было закрыто: при входе и при
  /// возврате из фона. Сервер отдаёт их один раз и сразу помечает.
  Future<void> checkPending() async {
    final g = _group;
    if (g.isEmpty || g == 'solo') return;
    try {
      final res = await PocketBaseService().pb.send('/api/group/snowball', method: 'POST', body: {'groupId': g, 'pending': true});
      if (res is Map && g == _group) hit((res['count'] as num?)?.toInt() ?? 0);
    } catch (e) {
      debugPrint('SnowballService.checkPending: $e');
    }
  }

  @visibleForTesting
  void debugReset() {
    current.value = null;
    _group = '';
    _partner = '';
    _lastThrow = null;
    _received.clear();
    debugAck = null;
  }
}
