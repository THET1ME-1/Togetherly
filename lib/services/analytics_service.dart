import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'pocketbase_service.dart';

/// Своя аналитика: экраны, действия, воронка новичка, показы рекламы.
///
/// После ухода с Firebase статистики не осталось никакой, а по таблицам видно
/// только «у пары есть запись в memories» — ни какие экраны открывают, ни где
/// обрывается путь до пары, этого не узнать.
///
/// Событие ложится в очередь в памяти и уходит пачкой раз в минуту, при
/// сворачивании приложения и при выходе. Сети нет — пачка возвращается в
/// очередь и поедет со следующей; очередь переполнилась — выбрасываем самое
/// старое. Синхронизацию это не задевает: отправка идёт своим запросом мимо
/// PocketBase и без ожидания.
///
/// Приватность: `uid` уходит как есть, но сервер хранит только его хеш с
/// собственной солью — связки «человек → его экраны» в базе нет. Ни текстов,
/// ни имён, ни ссылок событие не несёт: имя экрана, имя действия и числа.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  /// Куда шлём пачки — тот же домен, что и остальное API.
  static String get _endpoint =>
      '${PocketBaseService.baseUrl}/api/stats/collect';

  /// Потолок очереди. Дальше выбрасываем самые старые: копить их бесконечно
  /// вреднее, чем потерять хвост статистики.
  static const int _maxQueue = 300;

  /// Как часто сбрасываем накопленное.
  static const Duration _interval = Duration(minutes: 1);

  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  bool _sending = false;
  String _version = '';

  /// Наблюдатель для `MaterialApp.navigatorObservers`: считает открытия
  /// экранов и время на них, не требуя ни строчки в самих экранах.
  late final NavigatorObserver observer = _ScreenObserver(this);

  Future<void> init() async {
    if (_timer != null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _version = '';
    }
    _timer = Timer.periodic(_interval, (_) => unawaited(flush()));
  }

  /// Сбрасывает накопленное. Зовётся по таймеру, при сворачивании и на выходе.
  Future<void> flush() async {
    if (_sending || _queue.isEmpty) return;
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return; // до входа отправлять некому и незачем

    _sending = true;
    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();
    try {
      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'uid': uid,
              'platform': Platform.isIOS ? 'ios' : 'android',
              'version': _version,
              'events': batch,
            }),
          )
          .timeout(const Duration(seconds: 10));
      // 4xx — пачка кривая, повторять смысла нет. 5xx — сервер прилёг, вернём.
      if (res.statusCode >= 500) _requeue(batch);
    } catch (_) {
      _requeue(batch);
    } finally {
      _sending = false;
    }
  }

  void _requeue(List<Map<String, dynamic>> batch) {
    _queue.insertAll(0, batch);
    _trim();
  }

  void _trim() {
    if (_queue.length <= _maxQueue) return;
    _queue.removeRange(0, _queue.length - _maxQueue);
  }

  void _add(String kind, String name, {int? ms}) {
    if (kDebugMode) return; // отладочные запуски статистику не портят
    _queue.add({
      'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'kind': kind,
      'name': name,
      if (ms != null) 'ms': ms,
    });
    _trim();
  }

  // ── Что считаем ────────────────────────────────────────────────────────────

  /// Экран закрыли: [ms] — сколько на нём пробыли.
  void logScreen(String name, {int? ms}) => _add('screen', name, ms: ms);

  /// Действие внутри приложения.
  void logAction(String name) => _add('action', name);

  /// Шаг пути новичка: `signup`, `invite_screen`, `invite_sent`,
  /// `pair_created`, `first_action`.
  void logFunnel(String step) => _add('funnel', step);

  /// Рекламный блок попал на экран. [slot] — место: `home`, `memlane`,
  /// `widgets`. Свой счёт рядом с кабинетом РСЯ показывает, где теряются
  /// показы: там на 4,9 тысячи запросов приходилось 1,5 тысячи показов.
  void logAdShown(String slot) => _add('ad', slot);

  // ── Прежний API: эти вызовы расставлены по коду ещё со времён Firebase ────

  Future<void> setUserId(String? uid) async {}

  Future<void> logPairConnected({required String groupId}) async =>
      logFunnel('pair_created');

  Future<void> logMemoryAdded({required String type}) async =>
      logAction('memory_added');

  Future<void> logMoodSet({required String label}) async =>
      logAction('mood_set');

  Future<void> logCanvasOpened({required bool shared}) async =>
      logAction(shared ? 'canvas_shared' : 'canvas_solo');

  Future<void> logVibeSent({required String vibeType}) async =>
      logAction('vibe_sent');

  Future<void> logMissYouSent() async => logAction('miss_you_sent');
}

/// Считает экраны по переходам навигатора.
///
/// Имя берём из `RouteSettings.name` — оно проставлено у экранов приложения
/// (`/draw`, `/coloring_catalogue`, …). Безымянные маршруты пропускаем: нижних
/// листов и диалогов сотни, и статистика от них только шумела бы.
class _ScreenObserver extends NavigatorObserver {
  _ScreenObserver(this._analytics);

  final AnalyticsService _analytics;
  final Map<String, DateTime> _openedAt = {};

  String? _nameOf(Route<dynamic>? route) {
    final raw = route?.settings.name ?? '';
    final name = raw.replaceAll('/', '');
    return name.isEmpty ? null : name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _nameOf(route);
    if (name != null) _openedAt[name] = DateTime.now();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _nameOf(route);
    if (name == null) return;
    final opened = _openedAt.remove(name);
    _analytics.logScreen(
      name,
      ms: opened == null
          ? null
          : DateTime.now().difference(opened).inMilliseconds,
    );
  }
}
