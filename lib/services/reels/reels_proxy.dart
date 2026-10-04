import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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

  static Future<void> enable() async {
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
