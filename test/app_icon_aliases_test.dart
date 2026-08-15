import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/app_icon_service.dart';

/// Вариант иконки живёт в ЧЕТЫРЁХ местах разом: каталог в Dart, `ICON_ALIASES`
/// в `MainActivity.kt`, `<activity-alias>` в манифесте и название в словаре.
/// Забыть одно из них легко, а видно это только на устройстве: смена иконки
/// молча отвечает отказом либо лончер показывает не тот значок.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt',
  ).readAsStringSync();

  test('у каждой иконки есть alias в манифесте и строка в MainActivity', () {
    for (final o in AppIconService.options) {
      expect(
        kotlin.contains('"${o.id}" to ".Icon'),
        isTrue,
        reason: 'id ${o.id} не заведён в ICON_ALIASES',
      );
      final alias = RegExp(r'"' + o.id + r'" to "(\.\w+)"').firstMatch(kotlin)!;
      expect(
        manifest.contains('android:name="${alias.group(1)}"'),
        isTrue,
        reason: 'alias ${alias.group(1)} не объявлен в манифесте',
      );
    }
  });

  test('включён ровно один alias, и это иконка по умолчанию', () {
    final enabled = RegExp(
      r'android:name="(\.Icon\w+)"\s+android:enabled="true"',
    ).allMatches(manifest).map((m) => m.group(1)).toList();
    expect(enabled, hasLength(1));

    final defaultAlias = RegExp(
      r'"' + AppIconService.defaultId + r'" to "(\.\w+)"',
    ).firstMatch(kotlin)!.group(1);
    expect(enabled.single, defaultAlias);
  });

  test('у каждой иконки есть название на всех языках', () {
    final dict = File('lib/l10n/dict/app_icons.dart').readAsStringSync();
    for (final o in AppIconService.options) {
      expect(
        dict.contains("'appicon_${o.id}'"),
        isTrue,
        reason: 'нет названия appicon_${o.id}',
      );
    }
  });

  test('картинка превью лежит на диске и объявлена в pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final o in AppIconService.options) {
      final asset = o.asset;
      if (asset == null) continue;
      expect(File(asset).existsSync(), isTrue, reason: 'нет файла $asset');
      final dir = asset.substring(0, asset.lastIndexOf('/') + 1);
      expect(
        pubspec.contains('- $dir') || pubspec.contains('- $asset'),
        isTrue,
        reason: '$asset не попадёт в сборку: нет записи в pubspec',
      );
    }
  });
}
