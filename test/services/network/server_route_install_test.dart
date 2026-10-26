import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/network/server_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Обход ставится всем телефонам (26.10.2026). С 24 по 26.10.2026 его ставили
// только Украине и США по поясу и языку: через обход не поднимался сокет
// Centrifugo (порт 0). Страну по телефону не угадать, а запасной путь нужен и
// украинцу на московском времени, и тем, кому режут Timeweb в Европе.
void main() {
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => HttpOverrides.global = null);

  test('обход ставится при любом языке и поясе', () async {
    await ServerRoute.install();
    expect(HttpOverrides.current, isA<ServerRouteOverrides>());
  });

  test('запомненное в 1.39.1 «обход не нужен» больше ничего не решает', () async {
    SharedPreferences.setMockInitialValues({'server_route_wanted': false});
    await ServerRoute.install();
    expect(HttpOverrides.current, isA<ServerRouteOverrides>());
  });

  test('запомненный запасной путь поднимается при установке', () async {
    ServerRoute.instance = ServerRoute(
      loadSpareSince: () async => 1,
      saveSpareSince: (_) async {},
    );
    addTearDown(() => ServerRoute.instance = ServerRoute());
    await ServerRoute.install();
    expect(ServerRoute.instance.onSpare, isTrue);
  });

  test('обход ставит каждая точка входа: у движков свои глобалы', () {
    String body(String path, String start) {
      final text = File(path).readAsStringSync();
      final at = text.indexOf(start);
      expect(at, isNot(-1), reason: '$start в $path');
      return text.substring(at, text.indexOf('\n}', at));
    }

    const main = 'lib/main.dart';
    for (final start in [
      'void main() async {',
      'Future<void> widgetPushRefresh() async {',
      'Future<void> _homeWidgetBackgroundCallback(',
    ]) {
      expect(body(main, start), contains('await ServerRoute.install();'),
          reason: start);
    }
    expect(
      File('lib/services/widget_background_refresh_service.dart').readAsStringSync(),
      contains('await ServerRoute.install();'),
    );
    expect(
      File('lib/services/push_background_service.dart').readAsStringSync(),
      contains('await ServerRoute.install();'),
    );
  });

  test('канала часового пояса больше нет ни в Dart, ни в нативе', () {
    final kotlin = File('android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt')
        .readAsStringSync();
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(kotlin, isNot(contains('love_app/time_zone')));
    expect(swift, isNot(contains('love_app/time_zone')));
    expect(swift, isNot(contains('setupTimeZoneChannel')));
  });
}
