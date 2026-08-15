import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож кнопок «открыть в картах» из воспоминания.
///
/// Жалоба от 14.08.2026: «В воспоминаниях не открываются координаты в 2ГИС».
/// 2ГИС у человека стоял — до системы запрос просто не доходил, и лист выдавал
/// «приложение не установлено».
///
/// Барьеров оказалось три, и каждый в одиночку убивает кнопку:
///
/// 1. **Android 11+ прячет чужие приложения.** `canLaunchUrl('dgis://…')`
///    отвечает false, пока схема не объявлена в `<queries>` манифеста. Это же
///    правило действует и для обычных `https`: без `<intent>` с `VIEW` и
///    `scheme="https"` не проходили и Google Maps, Waze и Apple Maps — то есть
///    на Android не работала НИ ОДНА из пяти кнопок.
/// 2. **iOS требует `LSApplicationQueriesSchemes`.** Без списка `canOpenURL`
///    всегда false для чужих схем; `http`/`https` объявлять не надо.
/// 3. **Своя проверка `safeLaunchUrl`.** Схема, которой нет в `_knownSchemes`,
///    отсекается до `launchUrl` — даже если первые два барьера сняты.
///
/// Тест идёт от каталога карт в коде: любая новая карта со своей схемой обязана
/// быть объявлена во всех трёх местах, иначе её кнопка молча мертва.
void main() {
  final catalog = File('lib/screens/memory_lane/detail.dart').readAsStringSync();
  final schemes = RegExp(r"url:\s*'([a-z][a-z0-9+.-]*)://")
      .allMatches(catalog)
      .map((m) => m.group(1)!)
      .toSet();

  test('каталог карт разобрался', () {
    expect(schemes, isNotEmpty, reason: 'не нашёл ни одной ссылки на карты');
    expect(schemes, contains('dgis'));
  });

  test('чужие схемы объявлены в <queries> манифеста Android', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final queries = RegExp(r'<queries>(.*?)</queries>', dotAll: true)
        .firstMatch(manifest)
        ?.group(1);
    expect(queries, isNotNull, reason: 'в манифесте нет блока <queries>');

    final missing = schemes
        .where((s) => !RegExp('scheme="$s"').hasMatch(queries!))
        .toList();
    expect(
      missing,
      isEmpty,
      reason: 'схемы не объявлены в <queries>, canLaunchUrl вернёт false: '
          '${missing.join(", ")}',
    );
  });

  test('свои схемы объявлены в LSApplicationQueriesSchemes на iOS', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final list = RegExp(
      r'<key>LSApplicationQueriesSchemes</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist)?.group(1);
    expect(list, isNotNull,
        reason: 'в Info.plist нет LSApplicationQueriesSchemes');

    // http/https на iOS объявлять не требуется — canOpenURL их и так знает.
    final foreign = schemes.where((s) => s != 'http' && s != 'https');
    final missing =
        foreign.where((s) => !RegExp('<string>$s</string>').hasMatch(list!));
    expect(missing, isEmpty,
        reason: 'схемы не объявлены на iOS: ${missing.join(", ")}');
  });

  test('схемы карт проходят через safeLaunchUrl', () {
    final source = File('lib/utils/safe_launch.dart').readAsStringSync();
    final known = RegExp(r'_knownSchemes\s*=\s*\{(.*?)\}', dotAll: true)
        .firstMatch(source)!
        .group(1)!;

    final missing = schemes.where((s) => !known.contains("'$s'")).toList();
    expect(
      missing,
      isEmpty,
      reason: 'safeLaunchUrl отсечёт эти схемы до системы: '
          '${missing.join(", ")}',
    );
  });
}
