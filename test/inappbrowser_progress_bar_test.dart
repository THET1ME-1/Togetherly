import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Комната на iPhone в 1.37 открывалась нативным окном (`InAppBrowser`) и
/// падала при каждом открытии: `loadView` плагина зовёт `prepareWebView`
/// раньше, чем создаёт полосу загрузки, а мы просим её скрыть
/// (`hideProgressBar: true`), и строка `progressBar.isHidden = true` трогает
/// ещё пустое поле. В Bugsink это `EXC_BREAKPOINT: 🤯 > close` (19.10.2026,
/// пятеро за полдня и обращение 343: «смотрю рекламу и приложение вылетает»).
void main() {
  final src = File('third_party/flutter_inappwebview_ios/ios/flutter_inappwebview_ios/'
          'Sources/flutter_inappwebview_ios/InAppBrowser/InAppBrowserWebViewController.swift')
      .readAsStringSync();

  String bodyOf(String signature) {
    final start = src.indexOf(signature);
    expect(start, isNot(-1), reason: 'нет $signature');
    var depth = 0;
    for (var i = src.indexOf('{', start); i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}' && --depth == 0) return src.substring(start, i);
    }
    fail('не закрыта $signature');
  }

  test('полоса загрузки создаётся раньше, чем окно строит панель', () {
    final load = bodyOf('public override func loadView()');
    final bar = load.indexOf('progressBar = UIProgressView(');
    final prepare = load.indexOf('prepareWebView()');
    expect(bar, isNot(-1), reason: 'loadView больше не создаёт полосу');
    expect(prepare, isNot(-1), reason: 'loadView больше не зовёт prepareWebView');
    expect(bar < prepare, isTrue,
        reason: 'prepareWebView трогает progressBar, пустое поле роняет приложение');
  });

  test('панель окна не трогает полосу, если её нет', () {
    final prepare = bodyOf('public func prepareWebView()');
    expect(prepare, isNot(contains('progressBar.isHidden')),
        reason: 'progressBar — неявно развёрнутое поле, писать через progressBar?.');
  });
}
