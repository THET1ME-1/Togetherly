import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

/// Посредник для TikTok, пока открыты «Ленты вдвоём».
///
/// TikTok закрывает Россию только на страницах и данных (`ru_cross_border_block`
/// по адресу), а видео и статику отдаёт напрямую. Поэтому через посредника —
/// tinyproxy на Contabo, который пускает только домены tiktok.com, — идут
/// ровно эти страницы; всё остальное, включая сами ролики, — мимо. Без
/// пароля намеренно: как VPN он бесполезен.
///
/// Включается на весь браузер приложения (у WebView это общая настройка),
/// поэтому и снимается сразу при выходе из лент.
class ReelsProxy {
  ReelsProxy._();

  static const String _url = 'http://169.58.6.158:8899';
  static const List<String> _hosts = ['tiktok.com', 'www.tiktok.com', 'm.tiktok.com'];
  static bool _on = false;

  /// Закрыт ли TikTok с этого адреса. Из России страница ролика приходит с
  /// `"statusMsg":"ru_cross_border_block"` (код 10204), из других стран — с
  /// кодом 0. Ответ помним на весь запуск: адрес за сеанс не меняется.
  static bool? _blocked;

  static Future<bool> _isBlocked() async {
    final known = _blocked;
    if (known != null) return known;
    try {
      final res = await http
          .get(Uri.parse('https://www.tiktok.com/@tiktok/video/7654645616496168200'), headers: {'User-Agent': _desktopUa})
          .timeout(const Duration(seconds: 12));
      return _blocked = res.body.contains('ru_cross_border_block');
    } catch (_) {
      // TikTok не ответил вовсе — похоже на блокировку, посредник поможет.
      return _blocked = true;
    }
  }

  static const String _desktopUa =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';

  /// Включить посредника, если TikTok с этого адреса закрыт. Где он открыт,
  /// ходим напрямую: лишний круг через Францию только замедлял бы плеер.
  static Future<void> enable() async {
    if (!await _isBlocked()) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // «Только эти хосты через посредника» — обратный список обхода.
        final ok = await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE) &&
            await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE_REVERSE_BYPASS);
        if (!ok) return;
        await ProxyController.instance().setProxyOverride(
          settings: ProxySettings(proxyRules: [ProxyRule(url: _url)], bypassRules: _hosts, reverseBypassEnabled: true),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS 17+: правило с `matchDomains` касается только этих доменов.
        await ProxyController.instance().setProxyOverride(
          settings: ProxySettings(proxyRules: [ProxyRule(url: _url, matchDomains: _hosts)]),
        );
      } else {
        return;
      }
      _on = true;
    } catch (e) {
      debugPrint('ReelsProxy: не включился: $e');
    }
  }

  static Future<void> disable() async {
    if (!_on) return;
    _on = false;
    try {
      await ProxyController.instance().clearProxyOverride();
    } catch (_) {}
  }
}
