import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../models/reel_queue.dart';
import '../../models/reels_source.dart';

/// Лента площадки этого телефона — в скрытом браузере.
///
/// Человек как будто сам листает ленту площадки: куки браузера живут между
/// запусками, поэтому рекомендации у каждого свои и учатся на том, что он
/// смотрит. Страница ничего не показывает и звука не даёт — она только
/// приносит номера роликов, а смотрят оба в комнате официальным плеером.
///
/// Номера ловит скрипт в начале документа: перехват `fetch` и
/// `XMLHttpRequest`, ответ ленты разбирается правилом своей площадки
/// ([script]). ВК и Дзен кладут первые ролики прямо в разметку — их скрипт
/// берёт и оттуда.
class ReelsFeed {
  ReelsFeed(this.source, {this.onIds});

  final ReelsSource source;

  /// Пришли новые номера — комната получает их сразу, не дожидаясь вопроса.
  final void Function(List<String> ids)? onIds;

  static const String _desktopUa =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';

  final ReelQueue _queue = ReelQueue();
  HeadlessInAppWebView? _view;
  Completer<void>? _arrived;
  DateTime _lastNav = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  /// Скрипт страницы: перехват ответов ленты, тишина, согласие на куки.
  /// Правила площадок повторяет разведка (`reels_source.dart`).
  static String script(ReelsSource source) => '''
(function(){
  if (window.__tgReels) return; window.__tgReels = 1;
  var SRC = '${source.key}';
  var tell = function(ids){ if (ids.length) try { window.flutter_inappwebview.callHandler('reelIds', ids); } catch (e) {} };
  var uniq = function(a){ var s = {}, o = []; a.forEach(function(x){ if (x && !s[x]) { s[x] = 1; o.push(x); } }); return o; };
  var all = function(text, re, map){ var out = [], m; while ((m = re.exec(text))) out.push(map ? map(m) : m[1]); return out; };
  var RULES = {
    shorts: { url: /youtubei\\/v1\\/reel\\/reel_watch_sequence/, pick: function(t){ return all(t, /"videoId":"([A-Za-z0-9_-]{11})"/g); } },
    tiktok: { url: /api\\/(recommend|preload)\\/item_list/, pick: function(t){ try { return (JSON.parse(t).itemList || []).map(function(i){ return String(i.id); }); } catch (e) { return []; } } },
    rutube: { url: /shorts\\/lenta/, pick: function(t){ return all(t, /"id":"([0-9a-f]{32})"/g); } },
    vk: { url: /shortVideo\\.getRecom/, pick: function(t){ return all(t, /video_ext\\.php\\?oid=(-?\\d+)&(?:amp;)?id=(\\d+)&(?:amp;)?hash=([0-9a-f]+)/g, function(m){ return m[1] + '_' + m[2] + '_' + m[3]; }); } },
    dzen: { url: /video-recommend/, pick: function(t){ return all(t, /"videoContentId":"([A-Za-z0-9_-]{6,})"/g); } }
  };
  var R = RULES[SRC];
  var heard = function(u, t){ try { if (R.url.test(String(u || ''))) tell(uniq(R.pick(t))); } catch (e) {} };
  var f = window.fetch;
  if (f) window.fetch = function(input){
    var u = typeof input === 'string' ? input : (input && input.url) || '';
    return f.apply(this, arguments).then(function(r){
      try { if (R.url.test(u)) r.clone().text().then(function(t){ heard(u, t); }, function(){}); } catch (e) {}
      return r;
    });
  };
  var open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m, u){ this.__tgU = u; return open.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function(){
    var x = this;
    x.addEventListener('load', function(){ try { heard(x.__tgU, x.responseText); } catch (e) {} });
    return send.apply(this, arguments);
  };
  // ВК и Дзен первые ролики кладут прямо в разметку.
  if (SRC === 'vk' || SRC === 'dzen') document.addEventListener('DOMContentLoaded', function(){
    try { tell(uniq(R.pick(document.documentElement.innerHTML))); } catch (e) {}
  });
  // Ни звука: ролик здесь играет только ради того, чтобы площадка его
  // засчитала, слушают его в комнате.
  var hush = function(v){ try { v.muted = true; v.volume = 0; if (window.__tgStop) v.pause(); } catch (e) {} };
  var play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function(){ hush(this); return play.apply(this, arguments); };
  setInterval(function(){ document.querySelectorAll('video,audio').forEach(hush); }, 400);
  // Просмотр засчитан — дальше ролик не крутим: бесконечный повтор в
  // скрытом браузере грел телефон и тормозил ленту в комнате.
  setTimeout(function(){ window.__tgStop = 1; }, 12000);
  // Экран согласия на куки (часть стран Европы) — отказываемся от лишнего.
  if (/^consent\\./.test(location.hostname)) setTimeout(function(){
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
      initialUrlRequest: URLRequest(url: WebUri(source.home)),
      initialSize: source.desktop ? const Size(1280, 900) : const Size(390, 844),
      initialUserScripts: UnmodifiableListView([
        UserScript(source: script(source), injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
      ]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        userAgent: source.desktop ? _desktopUa : null,
        preferredContentMode: source.desktop ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.RECOMMENDED,
      ),
      onWebViewCreated: (c) {
        c.addJavaScriptHandler(
          handlerName: 'reelIds',
          callback: (args) {
            final ids = args.isNotEmpty && args.first is List ? (args.first as List) : const [];
            _accept(ids);
            return null;
          },
        );
      },
      onConsoleMessage: (_, m) {
        if (kDebugMode) debugPrint('ReelsFeed(${source.key}): ${m.message}');
      },
    );
    _view = view;
    _lastNav = DateTime.now();
    try {
      await view.run();
    } catch (e) {
      debugPrint('ReelsFeed: скрытая страница не поднялась: $e');
    }
  }

  void _accept(List<Object?> ids) {
    final before = _queue.length;
    final added = _queue.add(ids);
    if (added == 0) return;
    debugPrint('ReelsFeed(${source.key}): +$added (в запасе ${_queue.length})');
    _arrived?.complete();
    _arrived = null;
    // Комнату будим, только если запас был пуст: иначе она сама спросит.
    if (before == 0 && onIds != null) onIds!(_queue.take(added.clamp(0, 6)));
  }

  /// До [n] номеров. Пусто — ждём ленту до [wait], пока страница раскачается.
  Future<List<String>> take(int n, {Duration wait = const Duration(seconds: 14)}) async {
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
  /// Площадка засчитывает просмотр и отвечает похожими — так рекомендации
  /// идут за тем, что пара правда смотрит.
  Future<void> watching(String id) async {
    if (!ReelQueue.isId(id)) return;
    _queue.markShown(id);
    final url = source.watchUrl(id);
    if (url.isNotEmpty) await _go(url);
  }

  /// «Обновить рекомендации»: запас в сторону, лента открывается заново.
  Future<void> refresh() async {
    _queue.dropPending();
    await _go(source.home);
  }

  /// Запас кончается: Shorts листаем дальше от последнего номера, остальные
  /// открываем заново — каждая загрузка ленты приносит свежую подборку.
  void _refill() {
    // Страница только что открыта и ещё отвечает — не дёргаем её.
    if (DateTime.now().difference(_lastNav) < const Duration(seconds: 6)) return;
    final last = _queue.last;
    final url = source == ReelsSource.shorts && last != null ? source.watchUrl(last) : source.home;
    unawaited(_go(url));
  }

  Future<void> _go(String url) async {
    final c = _view?.webViewController;
    if (c == null || _disposed) return;
    _lastNav = DateTime.now();
    try {
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } catch (e) {
      debugPrint('ReelsFeed: переход не удался: $e');
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
