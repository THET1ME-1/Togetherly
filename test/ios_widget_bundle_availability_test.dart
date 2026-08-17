// В бандле виджетов не может быть ни одной ветки `if #available`.
//
// Каждая такая ветка компилируется в
// `WidgetBundleBuilder.buildLimitedAvailability`, и расширение падает внутри
// неё с SIGTRAP, когда chronod запускает его за списком виджетов. Дескрипторы
// не приходят, галерея пустеет у ВСЕХ виджетов, а не только у условных. Люди
// пишут «нажимаю плюс, а приложения Togetherly нет» — и по коду это не видно
// совсем: собирается, подписывается, устанавливается, регистрируется.
//
// Стек, снятый с релизной сборки расширения 1.28.4+195 (файл .ips из
// симулятора, шаг «Падало ли расширение на самом деле» в ios-widget-registry):
//   libswiftCore  _assertionFailure(_:_:file:line:flags:)
//   Togetherly    WidgetBundleBuilder.buildLimitedAvailability(_:)
//   Togetherly    TogetherlyWidgetBundle.body.getter
//   SwiftUI       WidgetBundleBodyAccessor.updateBody(of:changed:)
//
// Прежнее правило этого теста — «условная ветка живёт рядом с безусловными
// виджетами, а не составляет блок целиком» — было слабее, чем нужно: ветку
// перенесли в общий блок (5900fff2, уехало в 1.28.4+195), и на телефоне не
// изменилось НИЧЕГО. Ветка осталась, а с ней и вызов.
//
// Вместо ветвей минимальная версия расширения поднята до iOS 17: тогда и
// accessory экрана блокировки (iOS 16+), и конфигурируемые фото на AppIntents
// (iOS 17+) объявляются безусловно. Внутри вьюх `if #available` разрешён — там
// работает `ViewBuilder`, а не `WidgetBundleBuilder`, и он не падает.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final raw =
      File('ios/TogetherlyWidget/TogetherlyWidgetBundle.swift').readAsStringSync();
  // Комментарии выкидываем до разбора: в них те же слова, что в коде.
  final source = raw
      .split('\n')
      .map((l) => l.trimLeft().startsWith('//') ? '' : l)
      .join('\n');

  test('в бандле нет ни одной ветки доступности', () {
    final offenders = <String>[];
    for (final block in _bundleBlocks(source).entries) {
      if (block.value.contains('#available')) offenders.add(block.key);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'ветка доступности в бандле роняет расширение с SIGTRAP внутри '
          'buildLimitedAvailability, и галерея пустеет целиком: '
          '${offenders.join(', ')}. Нужную версию задаёт '
          'IPHONEOS_DEPLOYMENT_TARGET расширения, а не `if #available`.',
    );
  });

  test('минимальная версия расширения не ниже 17.0', () {
    // Без неё конфигурируемые фото (AppIntentConfiguration, iOS 17+) и
    // accessory экрана блокировки (iOS 16+) не объявить безусловно, и ветка
    // доступности вернётся в бандл.
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final targets = RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = (\d+)\.\d+;[\s\S]{0,400}?'
      r'PRODUCT_BUNDLE_IDENTIFIER = com\.togetherly\.love\.TogetherlyWidget;',
    ).allMatches(project);

    expect(targets, isNotEmpty, reason: 'не нашёл настроек расширения — разбор сломан');
    for (final m in targets) {
      expect(
        int.parse(m.group(1)!),
        greaterThanOrEqualTo(17),
        reason: 'у расширения минимальная версия ниже 17.0',
      );
    }
  });

  test('виджеты экрана блокировки на месте', () {
    // Чинить падение выбрасыванием функции нельзя: их отсутствие — тоже
    // жалоба («виджетов на экране блокировки нет», 13.08.2026).
    for (final widget in ['LockDaysWidget', 'LockMissWidget', 'LockMoodWidget']) {
      expect(source, contains('$widget()'), reason: '$widget пропал из бандла');
    }
  });

  test('конфигурируемые фото на месте', () {
    for (final widget in [
      'SelfPhotoWidgetConfigurable',
      'PartnerPhotoWidgetConfigurable',
      'PhotoDayWidgetConfigurable',
    ]) {
      expect(source, contains('$widget()'), reason: '$widget пропал из бандла');
    }
  });
}

/// Тела всех `@WidgetBundleBuilder`-свойств: имя → содержимое фигурных скобок.
Map<String, String> _bundleBlocks(String source) {
  final blocks = <String, String>{};
  final header = RegExp(r'@WidgetBundleBuilder\s+var\s+(\w+)\s*:\s*some Widget\s*\{');
  for (final match in header.allMatches(source)) {
    final body = _bracedBody(source, match.end - 1);
    if (body != null) blocks[match.group(1)!] = body;
  }
  return blocks;
}

/// Содержимое от открывающей скобки до парной ей закрывающей.
String? _bracedBody(String source, int openBrace) {
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(openBrace + 1, i);
    }
  }
  return null;
}
