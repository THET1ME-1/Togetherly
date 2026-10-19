import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Движок браузеров на Android один на все окна приложения. Когда система
/// убивает его (не хватило памяти) или он падает, каждое окно получает
/// `onRenderProcessGone`, и если хоть одно его не обработало, Android уносит
/// приложение целиком. Плагин обрабатывает это только с флагом
/// `useOnRenderProcessGone` (`InAppWebViewClient.onRenderProcessGone`).
///
/// Совместная лента держит два браузера разом: свою страницу с тремя
/// плеерами и скрытую страницу площадки. Жалоба: «вылетало при попытке
/// пролистать совместную ленту» (обращение 297, Redmi Note 13, 18.10.2026).
void main() {
  final sources = {
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  };

  /// Текст между скобкой после [start] и парной ей.
  String call(String src, int start) {
    final open = src.indexOf('(', start);
    var depth = 0;
    for (var i = open; i < src.length; i++) {
      if (src[i] == '(') depth++;
      if (src[i] == ')' && --depth == 0) return src.substring(open, i + 1);
    }
    return src.substring(open);
  }

  test('настройки браузера включают обработку гибели движка', () {
    final missing = <String>[];
    var seen = 0;
    sources.forEach((path, src) {
      for (final m in RegExp(r'InAppWebViewSettings\(').allMatches(src)) {
        seen++;
        if (!call(src, m.start).contains('useOnRenderProcessGone: true')) {
          missing.add('$path:${'\n'.allMatches(src.substring(0, m.start)).length + 1}');
        }
      }
    });
    expect(seen, greaterThan(0), reason: 'Сторож перестал находить браузеры');
    expect(missing, isEmpty,
        reason: 'Без флага гибель движка роняет всё приложение');
  });

  test('каждый браузер поднимает себя заново после гибели движка', () {
    final missing = <String>[];
    var seen = 0;
    sources.forEach((path, src) {
      for (final m in RegExp(r'\b(Headless)?InAppWebView\(').allMatches(src)) {
        seen++;
        if (!call(src, m.start).contains('onRenderProcessGone:')) {
          missing.add('$path:${'\n'.allMatches(src.substring(0, m.start)).length + 1}');
        }
      }
    });
    expect(seen, greaterThan(1));
    expect(missing, isEmpty,
        reason: 'Мёртвая страница не оживёт сама: её надо создать заново');
  });
}
