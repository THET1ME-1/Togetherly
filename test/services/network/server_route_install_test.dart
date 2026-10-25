import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/network/server_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Обход ставится только телефонам, которым он нужен (24.10.2026). В 1.39 он
// стоял у всех, и мгновенная связь не поднималась ни у кого.
void main() {
  const russia = [Locale('ru', 'RU')];
  const ukraine = [Locale('uk', 'UA')];
  const kyiv = Duration(hours: 3);

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => HttpOverrides.global = null);

  test('Россия: обход не ставится, решение запомнено для фона', () async {
    final installed = await ServerRoute.install(
        fromDevice: true, locales: russia, utcOffset: kyiv);
    expect(installed, isFalse);
    expect(HttpOverrides.current, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ServerRoute.wantedKey), isFalse);
  });

  test('Украина: обход ставится, решение запомнено для фона', () async {
    final installed = await ServerRoute.install(
        fromDevice: true, locales: ukraine, utcOffset: kyiv);
    expect(installed, isTrue);
    expect(HttpOverrides.current, isA<ServerRouteOverrides>());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ServerRoute.wantedKey), isTrue);
  });

  test('фоновый движок берёт решение главного, а не свой язык', () async {
    SharedPreferences.setMockInitialValues({ServerRoute.wantedKey: false});
    final installed =
        await ServerRoute.install(locales: ukraine, utcOffset: kyiv);
    expect(installed, isFalse);
    expect(HttpOverrides.current, isNull);
  });

  test('фоновый движок без решения главного решает сам и не запоминает', () async {
    final installed =
        await ServerRoute.install(locales: ukraine, utcOffset: kyiv);
    expect(installed, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ServerRoute.wantedKey), isNull);
  });

  test('решает по стране только главный движок, фоновые берут запомненное', () {
    final main = File('lib/main.dart').readAsStringSync();
    final mainBody = main.substring(main.indexOf('void main() async {'));
    expect(
      mainBody.substring(0, mainBody.indexOf('\n}')),
      contains('ServerRoute.install(fromDevice: true)'),
    );
    final calls = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          ...RegExp(r'ServerRoute\.install\(fromDevice: true\)')
              .allMatches(file.readAsStringSync())
              .map((_) => file.path),
    ];
    expect(calls, ['lib/main.dart']);
  });
}
