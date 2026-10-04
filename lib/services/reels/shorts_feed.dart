import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../models/reel_queue.dart';

/// Лента YouTube Shorts этого телефона — в скрытом браузере.
///
/// Человек как будто сам листает m.youtube.com/shorts: куки браузера живут
/// между запусками, поэтому рекомендации у каждого свои и учатся на том, что
/// смотрели. Страница ничего не показывает и звука не даёт — она только
/// приносит номера роликов, а смотрят оба в комнате официальным плеером.
///
/// Номера приходят из ответа `youtubei/v1/reel/reel_watch_sequence`: его
/// страница просит сама, открыв ролик, и в нём около восьми следующих.
/// Перехват стоит на `fetch` и `XMLHttpRequest` в начале документа.
class ShortsFeed {
  ShortsFeed({this.onIds});

  /// Пришли новые номера — комната получает их сразу, не дожидаясь вопроса.
  final void Function(List<String> ids)? onIds;

  static const String home = 'https://m.youtube.com/shorts/';

  final ReelQueue _queue = ReelQueue();
  HeadlessInAppWebView? _view;
  Completer<void>? _arrived;
  DateTime _lastNav = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  /// Скрипт страницы: перехват ответов ленты, тишина, согласие на куки.
  static const String script = r'''
(function(){
  if (window.__tgShorts) return; window.__tgShorts = 1;
  var tell = function(text){
    try {
      var out = [], re = /"videoId":"([A-Za-z0-9_-]{11})"/g, m;
      while ((m = re.exec(text))) out.push(m[1]);
      if (out.length) window.flutter_inappwebview.callHandler('shortsIds', out);
    } catch (e) {}
  };
  var wanted = function(u){ return /youtubei\/v1\/reel\/reel_watch_sequence/.test(String(u || '')); };
  var f = window.fetch;
  if (f) window.fetch = function(input){
    var u = typeof input === 'string' ? input : (input && input.url) || '';
    return f.apply(this, arguments).then(function(r){
      try { if (wanted(u)) r.clone().text().then(tell, function(){}); } catch (e) {}
      return r;
    });
  };
  var open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m, u){ this.__tgU = u; return open.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function(){
    var x = this;
    x.addEventListener('load', function(){ try { if (wanted(x.__tgU)) tell(x.responseText); } catch (e) {} });
    return send.apply(this, arguments);
  };
  // Ни звука: ролик здесь играет только ради того, чтобы платформа его
  // засчитала, слушают его в комнате.
  var hush = function(v){ try { v.muted = true; v.volume = 0; if (window.__tgStop) v.pause(); } catch (e) {} };
  var play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function(){ hush(this); return play.apply(this, arguments); };
  setInterval(function(){ document.querySelectorAll('video,audio').forEach(hush); }, 400);
  // Просмотр засчитан — дальше ролик не крутим: бесконечный повтор в
  // скрытом браузере грел телефон и тормозил ленту в комнате.
  setTimeout(function(){ window.__tgStop = 1; }, 12000);
  // Экран согласия на куки (часть стран Европы) — отказываемся от лишнего.
  if (/^consent\./.test(location.hostname)) setTimeout(function(){
    var b = Array.prototype.slice.call(document.querySelectorAll('button')).find(function(x){
      return /reject|отклон|refuz|ablehnen|rechazar|refuser|rifiuta/i.test((x.textContent || '') + (x.getAttribute('aria-label') || ''));
    });
    if (b) b.click();
  }, 1500);
})();
''';

  /// Поднять скрытую страницу. Повторный вызов ничего не делает.
  Future<void> start() async {
    if (_view != null || _disposed) return;
    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(home)),
      initialSize: const Size(390, 844),
      initialUserScripts: UnmodifiableListView([
        UserScript(source: script, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
      ]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
      ),
      onWebViewCreated: (c) {
        c.addJavaScriptHandler(
          handlerName: 'shortsIds',
          callback: (args) {
            final ids = args.isNotEmpty && args.first is List ? (args.first as List) : const [];
            _accept(ids);
            return null;
          },
        );
      },
      onConsoleMessage: (_, m) {
        if (kDebugMode) debugPrint('ShortsFeed: ${m.message}');
      },
    );
    _view = view;
    _lastNav = DateTime.now();
    try {
      await view.run();
    } catch (e) {
      debugPrint('ShortsFeed: скрытая страница не поднялась: $e');
    }
  }

  void _accept(List<Object?> ids) {
    final before = _queue.length;
    final added = _queue.add(ids);
    if (added == 0) return;
    debugPrint('ShortsFeed: +$added (в запасе ${_queue.length})');
    _arrived?.complete();
    _arrived = null;
    // Комнату будим, только если запас был пуст: иначе она сама спросит.
    if (before == 0 && onIds != null) onIds!(_queue.take(added.clamp(0, 6)));
  }

  /// До [n] номеров. Пусто — ждём ленту до [wait], пока страница раскачается.
  Future<List<String>> take(int n, {Duration wait = const Duration(seconds: 12)}) async {
    if (_queue.length == 0) {
      _refill();
      final arrived = _arrived ??= Completer<void>();
      await arrived.future.timeout(wait, onTimeout: () {});
    }
    final out = _queue.take(n);
    if (_queue.length < 4) _refill();
    return out;
  }

  /// Ролик играет в комнате: скрытая страница открывает его тоже, без звука.
  /// Платформа засчитывает просмотр и отвечает следующими по нему — так
  /// рекомендации идут за тем, что пара правда смотрит.
  Future<void> watching(String id) async {
    if (!ReelQueue.isId(id)) return;
    _queue.markShown(id);
    await _go('https://m.youtube.com/shorts/$id');
  }

  /// Запас кончается: листаем скрытую ленту дальше от последнего номера.
  void _refill() {
    // Страница только что открыта и ещё отвечает — не дёргаем её.
    if (DateTime.now().difference(_lastNav) < const Duration(seconds: 4)) return;
    final last = _queue.last;
    unawaited(_go(last == null ? home : 'https://m.youtube.com/shorts/$last'));
  }

  Future<void> _go(String url) async {
    final c = _view?.webViewController;
    if (c == null || _disposed) return;
    _lastNav = DateTime.now();
    try {
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } catch (e) {
      debugPrint('ShortsFeed: переход не удался: $e');
    }
  }

  /// Приложение свернули: скрытая страница засыпает и не крутит ролик.
  Future<void> sleep() async {
    final c = _view?.webViewController;
    if (c == null) return;
    try {
      await c.evaluateJavascript(source: "window.__tgStop=1;document.querySelectorAll('video').forEach(function(v){try{v.pause()}catch(e){}});");
      if (defaultTargetPlatform == TargetPlatform.android) await c.pause();
    } catch (_) {}
  }

  /// Вернулись — страница снова слушает ленту (ролик не включаем).
  Future<void> wake() async {
    final c = _view?.webViewController;
    if (c == null) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) await c.resume();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    _arrived?.complete();
    _arrived = null;
    final v = _view;
    _view = null;
    try {
      await v?.dispose();
    } catch (_) {}
  }
}
