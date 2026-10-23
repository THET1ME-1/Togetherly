import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Что сейчас со связью до нашего сервера.
enum ServerReachState {
  /// Ещё не проверяли.
  unknown,

  /// Сервер отвечает.
  ok,

  /// Интернета нет вовсе: не отвечает ни наш сервер, ни чужие сайты.
  offline,

  /// Интернет есть, а наш сервер в этой сети закрыт. Так режут его часть
  /// провайдеров в Украине и США; помогает VPN или другая сеть.
  blocked,
}

/// Отличает «нет интернета» от «провайдер не пускает к нашему серверу» (TOG-16).
///
/// Отзыв из США 18.10.2026 и семь обращений из Украины за ночь на 23.10: интернет
/// у людей работал, а приложение писало «проверьте интернет», «некорректный
/// email» или крутило загрузку. Человек менял почту, переустанавливал
/// приложение и решал, что дело в нём. Когда до нашего сервера не достучаться,
/// служба спрашивает ещё и чужие сайты: отвечают они — значит, сеть есть, и
/// честный совет один: VPN или другая сеть.
///
/// Чужие сайты — Cloudflare и Википедия, а не Google: их провайдеры не режут, и
/// Google в проекте решили не тянуть. Запрос туда уходит только после обрыва
/// до нашего сервера и не чаще раза в минуту, данных человека он не несёт.
///
/// [ServerRoute] сообщает сюда об открытых и сорванных соединениях с нашим
/// сервером; экраны входа и регистрации зовут [check], когда запрос не прошёл.
class ServerReach {
  ServerReach({
    Future<bool> Function()? probeOurs,
    Future<bool> Function()? probeInternet,
    this.missedEvery = const Duration(minutes: 1),
    DateTime Function()? now,
  })  : _probeOurs = probeOurs ?? _ourServerAnswers,
        _probeInternet = probeInternet ?? _internetAnswers,
        _now = now ?? DateTime.now;

  /// Одна на процесс (и на каждый фоновый движок, как у [ServerRoute]).
  static ServerReach instance = ServerReach();

  final Future<bool> Function() _probeOurs;
  final Future<bool> Function() _probeInternet;
  final DateTime Function() _now;

  /// Обрыв соединения проверяет сеть не чаще этого.
  final Duration missedEvery;

  /// Последний ответ. Его слушает плашка поверх экранов.
  final ValueNotifier<ServerReachState> state =
      ValueNotifier(ServerReachState.unknown);

  Future<ServerReachState>? _running;
  DateTime? _lastMissedCheck;

  /// Соединение с нашим сервером открылось: он доступен.
  void reached() {
    state.value = ServerReachState.ok;
  }

  /// Соединение с нашим сервером сорвалось или затянулось. Проверяем сеть в
  /// фоне, но не чаще [missedEvery]: сорванных соединений за минуту бывают
  /// десятки, а ответ на все один.
  void missed() {
    final last = _lastMissedCheck;
    if (last != null && _now().difference(last) < missedEvery) return;
    _lastMissedCheck = _now();
    unawaited(check());
  }

  /// Проверяет сеть сейчас. Проверки внахлёст идут одним походом.
  Future<ServerReachState> check() {
    final running = _running;
    if (running != null) return running;
    final next = _run();
    _running = next;
    unawaited(next.whenComplete(() {
      if (identical(_running, next)) _running = null;
    }));
    return next;
  }

  Future<ServerReachState> _run() async {
    final answers = await Future.wait([
      _quietly(_probeOurs),
      _quietly(_probeInternet),
    ]);
    final verdict = answers[0]
        ? ServerReachState.ok
        : answers[1]
            ? ServerReachState.blocked
            : ServerReachState.offline;
    state.value = verdict;
    return verdict;
  }

  /// Упавшая проверка считается молчанием.
  static Future<bool> _quietly(Future<bool> Function() probe) async {
    try {
      return await probe();
    } catch (_) {
      return false;
    }
  }

  /// Наш сервер. Запрос идёт обычным путём, через [ServerRoute], то есть с
  /// запасным адресом: срок длиннее его нахлёста в шесть секунд.
  static Future<bool> _ourServerAnswers() => answers(
        Uri.parse('https://togetherly.day/api/health'),
        const Duration(seconds: 12),
      );

  /// Чужие сайты: хватает ответа любого.
  static Future<bool> _internetAnswers() async {
    final probes = [
      answers(Uri.parse('https://one.one.one.one/cdn-cgi/trace'),
          const Duration(seconds: 6)),
      answers(Uri.parse('https://www.wikipedia.org/static/favicon/wikipedia.ico'),
          const Duration(seconds: 6)),
    ];
    final done = Completer<bool>();
    var silent = 0;
    for (final probe in probes) {
      unawaited(probe.then((answered) {
        if (done.isCompleted) return;
        if (answered) {
          done.complete(true);
        } else if (++silent == probes.length) {
          done.complete(false);
        }
      }));
    }
    return done.future;
  }

  /// Ответил ли адрес хоть чем-нибудь за [limit]. Код ответа неважен: любой
  /// ответ значит, что сеть до адреса есть.
  @visibleForTesting
  static Future<bool> answers(Uri uri, Duration limit) async {
    final client = HttpClient();
    try {
      return await () async {
        final request = await client.getUrl(uri);
        final response = await request.close();
        await response.drain<void>();
        return true;
      }()
          .timeout(limit);
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
