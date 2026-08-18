import 'dart:async';
import 'reconnect_detector.dart';
import 'dart:convert';

import 'package:centrifuge/centrifuge.dart' as centrifuge;
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_service.dart';

/// Транспорт realtime через Centrifugo (замена встроенного SSE PocketBase).
///
/// ЗАЧЕМ: SSE PB держал долгоживущие read-транзакции SQLite → WAL не
/// чекпойнтился, PB упирался в CPU. Fan-out унесён в Centrifugo; PB лишь
/// публикует дельты (см. серверный хук centrifugo.pb.js). Этот сервис —
/// единственная точка, через которую `PbRealtimeService` получает живые дельты.
///
/// Архитектура:
///  • ОДНО WebSocket-соединение на приложение (`createClient`), connection-JWT
///    берётся у PB-эндпоинта /api/centrifugo/connection-token (auth-заголовок
///    добавляет сам pb-клиент). При истечении centrifuge сам зовёт getToken.
///  • На каждый КАНАЛ — одна Centrifugo-подписка (`_ChannelHub`) с ref-counting:
///    несколько watch*-слушателей одного канала делят одну подписку. subscription-
///    JWT (приватный канал) берётся у /api/centrifugo/subscription-token.
///  • Входящая публикация = JSON {event, collection, record}; парсим record в
///    RecordModel и раздаём слушателям, отфильтровав по collection и предикату.
class RtEvent {
  /// 'create' | 'update' | 'delete' — зеркало RecordSubscriptionEvent.action.
  final String action;
  final RecordModel? record;
  const RtEvent(this.action, this.record);
}

/// Сигнатура совпадает с pocketbase UnsubscribeFunc (`Future<void> Function()`).
typedef RtUnsub = Future<void> Function();

class CentrifugoService {
  CentrifugoService._();
  static final CentrifugoService instance = CentrifugoService._();
  factory CentrifugoService() => instance;

  /// Внешний TLS-порт Centrifugo (тот же домен/сертификат, что у PocketBase).
  /// Переопределяется: `--dart-define=CENTRIFUGO_WS=wss://.../connection/websocket`
  static const String _wsUrl = String.fromEnvironment(
    'CENTRIFUGO_WS',
    defaultValue: 'wss://togetherly.day/connection/websocket',
  );

  centrifuge.Client? _client;
  final Map<String, _ChannelHub> _channels = {};

  PocketBase get _pb => PocketBaseService().pb;

  /// Когда последний раз освежали сессию из-за 401. Centrifuge зовёт getToken
  /// по кругу, и без этой отметки каждый круг бил бы по authRefresh.
  static DateTime? _sessionRefreshedAt;

  /// Берёт токен у PocketBase, а на 401 сперва освежает сессию приложения.
  ///
  /// Токен Centrifugo живёт сутки, но выдаёт его PocketBase — и когда сессия
  /// приложения протухла, запрос отвечает 401. Раньше на этом всё кончалось:
  /// getToken бросал, клиент уходил на новый круг с тем же ответом, канал пары
  /// не подписывался, и сообщения появлялись только при перечитывании экрана —
  /// «сообщения не доходят или приходят с большой задержкой» (жалоба
  /// 18.08.2026; за два часа 149 отказов 401 на выдаче токена).
  static Future<String> askToken(
    PocketBase pb,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    Future<dynamic> send() =>
        pb.send(path, method: 'POST', body: body ?? const {});
    dynamic res;
    try {
      res = await send();
    } on ClientException catch (e) {
      if (e.statusCode != 401) rethrow;
      final now = DateTime.now();
      final last = _sessionRefreshedAt;
      if (last != null && now.difference(last) < const Duration(seconds: 30)) {
        rethrow;
      }
      _sessionRefreshedAt = now;
      // Сессию держит authStore: если её удалось освежить, повторяем запрос.
      await pb
          .collection('users')
          .authRefresh()
          .timeout(const Duration(seconds: 8));
      res = await send();
    }
    final token = (res is Map ? res['token'] : null) as String?;
    if (token == null || token.isEmpty) {
      throw StateError('centrifugo: пустой ответ на $path');
    }
    return token;
  }

  centrifuge.Client _ensureClient() {
    final existing = _client;
    if (existing != null) return existing;
    final c = centrifuge.createClient(
      _wsUrl,
      centrifuge.ClientConfig(
        name: 'togetherly',
        // token оставляем пустым → getToken вызовется и на первом коннекте, и
        // автоматически при истечении. НЕ бросаем UnauthorizedException на
        // транзиентный «ещё не залогинен» — обычная ошибка даёт backoff-ретрай,
        // а Unauthorized навсегда отрубил бы реконнект.
        getToken: (centrifuge.ConnectionTokenEvent e) async =>
            askToken(_pb, '/api/centrifugo/connection-token'),
      ),
    );
    // Восстановление после обрыва: подписки, которым важна полнота (общий
    // холст), по этому сигналу дотягивают пропущенное. Первое соединение сюда
    // не попадает — там список только что загрузили (см. ReconnectDetector).
    c.connected.listen((e) {
      if (kDebugMode) debugPrint('Centrifugo connected: ${e.client}');
      if (_reconnects.onConnected() && !_reconnected.isClosed) {
        _reconnected.add(null);
      }
    });
    c.disconnected.listen((e) {
      if (kDebugMode) debugPrint('Centrifugo disconnected: ${e.reason}');
      _reconnects.onDisconnected();
    });
    if (kDebugMode) {
      c.error.listen((e) => debugPrint('Centrifugo error: ${e.error}'));
    }
    _client = c;
    c.connect(); // fire-and-forget; centrifuge сам реконнектится
    return c;
  }

  final ReconnectDetector _reconnects = ReconnectDetector();
  final StreamController<void> _reconnected =
      StreamController<void>.broadcast();

  /// Сокет ожил после обрыва. Подписки, где потеря событий видна человеку,
  /// перечитывают по этому сигналу свой список.
  Stream<void> get reconnected => _reconnected.stream;

  _ChannelHub _hub(String channel) {
    _ensureClient();
    return _channels.putIfAbsent(
        channel, () => _ChannelHub(_ensureClient(), channel, _pb));
  }

  /// Подписаться на дельты [channel], отфильтрованные по [collection] и
  /// (опц.) предикату [match]. [onEvent] получает RtEvent с теми же полями,
  /// что у RecordSubscriptionEvent. Возвращает функцию отписки.
  Future<RtUnsub> subscribeDelta(
    String channel,
    String collection,
    void Function(RtEvent) onEvent, {
    bool Function(RecordModel)? match,
  }) async {
    final hub = _hub(channel);
    final listener = _ChannelListener(collection, match, onEvent);
    hub.add(listener);
    return () async {
      hub.remove(listener);
      if (hub.isEmpty) await hub.idle();
    };
  }

  /// Подписка на СЫРЫЕ публикации канала (не PB-дельты): для эфемерных данных,
  /// которые клиент публикует НАПРЯМУЮ в Centrifugo, минуя PocketBase (live-
  /// штрихи рисования — нет записи в БД, нет нагрузки на SQLite-writer).
  /// [onData] получает декодированный JSON публикации.
  Future<RtUnsub> subscribeRaw(
      String channel, void Function(Map<String, dynamic>) onData) async {
    final hub = _hub(channel);
    hub.addRaw(onData);
    return () async {
      hub.removeRaw(onData);
      if (hub.isEmpty) await hub.idle();
    };
  }

  /// Опубликовать [data] прямо в [channel] (требует серверный namespace с
  /// allow_publish_for_subscriber). Клиент должен быть подписан на канал —
  /// поднимаем подписку при необходимости. Ошибки глотаем: эфемерная публикация
  /// (потерянный кадр live-штриха некритичен).
  Future<void> publish(String channel, Map<String, dynamic> data) =>
      _hub(channel).publish(data);

  /// Полный сброс (logout/смена аккаунта): рвём все подписки и соединение.
  Future<void> reset() async {
    for (final hub in _channels.values) {
      await hub.dispose();
    }
    _channels.clear();
    final c = _client;
    _client = null;
    if (c != null) {
      try {
        await c.disconnect();
      } catch (_) {}
    }
  }
}

class _ChannelListener {
  final String collection;
  final bool Function(RecordModel)? match;
  final void Function(RtEvent) onEvent;
  _ChannelListener(this.collection, this.match, this.onEvent);
}

/// Одна Centrifugo-подписка на канал + раздача публикаций нескольким слушателям.
class _ChannelHub {
  final centrifuge.Client _client;
  final String channel;
  final PocketBase _pb;
  late final centrifuge.Subscription _sub;
  final List<_ChannelListener> _listeners = [];
  // Слушатели СЫРЫХ публикаций (эфемерные данные мимо PB, напр. live-штрихи).
  final List<void Function(Map<String, dynamic>)> _rawListeners = [];
  StreamSubscription<centrifuge.PublicationEvent>? _pubSub;
  bool _subscribed = false;

  _ChannelHub(this._client, this.channel, this._pb) {
    _sub = _client.newSubscription(
      channel,
      centrifuge.SubscriptionConfig(
        getToken: (centrifuge.SubscriptionTokenEvent e) async =>
            CentrifugoService.askToken(
          _pb,
          '/api/centrifugo/subscription-token',
          body: {'channel': e.channel},
        ),
      ),
    );
    _pubSub = _sub.publication.listen(_onPublication);
    _subscribed = true;
    _sub.subscribe();
  }

  void _onPublication(centrifuge.PublicationEvent ev) {
    try {
      final map = jsonDecode(utf8.decode(ev.data)) as Map<String, dynamic>;
      // Сырые слушатели (эфемерные публикации без PB-формата {collection,record}).
      if (_rawListeners.isNotEmpty) {
        for (final r in List<void Function(Map<String, dynamic>)>.of(_rawListeners)) {
          try {
            r(map);
          } catch (e) {
            debugPrint('Centrifugo raw listener error ($channel): $e');
          }
        }
      }
      final collection = map['collection'] as String?;
      final action = (map['event'] as String?) ?? 'update';
      RecordModel? rec;
      final recMap = map['record'];
      if (recMap is Map) {
        rec = RecordModel.fromJson(Map<String, dynamic>.from(recMap));
      }
      // Копия списка: слушатель может отписаться из колбэка.
      for (final l in List<_ChannelListener>.of(_listeners)) {
        if (l.collection != collection) continue;
        if (rec != null && l.match != null && !l.match!(rec)) continue;
        l.onEvent(RtEvent(action, rec));
      }
    } catch (e) {
      debugPrint('Centrifugo publication parse error ($channel): $e');
    }
  }

  void _ensureSubscribed() {
    // Канал мог быть переведён в idle (unsubscribe) при опустении — поднимаем.
    if (!_subscribed) {
      _subscribed = true;
      _sub.subscribe();
    }
  }

  void add(_ChannelListener l) {
    _listeners.add(l);
    _ensureSubscribed();
  }

  void remove(_ChannelListener l) => _listeners.remove(l);

  void addRaw(void Function(Map<String, dynamic>) l) {
    _rawListeners.add(l);
    _ensureSubscribed();
  }

  void removeRaw(void Function(Map<String, dynamic>) l) =>
      _rawListeners.remove(l);

  /// Публикация в канал (allow_publish_for_subscriber). Требует активной
  /// подписки. Ошибки глотаем — эфемерные данные, потеря кадра некритична.
  Future<void> publish(Map<String, dynamic> data) async {
    _ensureSubscribed();
    try {
      await _sub.publish(utf8.encode(jsonEncode(data)));
    } catch (e) {
      debugPrint('Centrifugo publish($channel) failed: $e');
    }
  }

  bool get isEmpty => _listeners.isEmpty && _rawListeners.isEmpty;

  /// Слушателей не осталось — освобождаем серверную подписку, но объект
  /// Subscription сохраняем (переиспользуем при повторном add → subscribe).
  Future<void> idle() async {
    if (!_subscribed) return;
    _subscribed = false;
    try {
      await _sub.unsubscribe();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _pubSub?.cancel();
    _pubSub = null;
    _listeners.clear();
    try {
      await _sub.unsubscribe();
    } catch (_) {}
    try {
      _client.removeSubscription(_sub);
    } catch (_) {}
  }
}
