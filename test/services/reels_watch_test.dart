import 'package:flutter_test/flutter_test.dart';

import 'package:love_app/services/reels/reels_telemetry.dart';

/// «Собираем ленту…» висело без конца (чат, 19.10.2026, iPhone, TikTok), и
/// понять, на каком шаге встало, было не по чему: скрытая страница площадки
/// живёт на телефоне, сервер её не видит, а лента не слала ничего.
void main() {
  final t0 = DateTime(2026, 10, 19, 18, 0);

  ReelsWatch watch() => ReelsWatch(source: 'tiktok', started: t0);

  test('ни одного ролика за 25 секунд — отчёт со всем, что известно', () {
    final w = watch()
      ..pages = 2
      ..lastHost = 'www.tiktok.com'
      ..lastTitle = 'Verify to continue'
      ..lastError = 'http 403'
      ..heard = 4;

    final r = w.check(t0.add(const Duration(seconds: 26)), proxyOn: true, blocked: true);

    expect(r, isNotNull);
    expect(r!['source'], 'tiktok');
    expect(r['ms'], 26000);
    expect(r['pages'], 2);
    expect(r['host'], 'www.tiktok.com');
    expect(r['title'], 'Verify to continue');
    expect(r['error'], 'http 403');
    expect(r['heard'], 4, reason: 'номера пришли, но ни один не лёг в запас');
    expect(r['ids'], 0);
    expect(r['proxy_on'], isTrue);
    expect(r['blocked'], isTrue);
  });

  test('номера пришли, но все отброшены — лента всё равно стоит', () {
    final w = watch()..heard = 12;
    expect(w.check(t0.add(const Duration(seconds: 30)), proxyOn: false, blocked: false), isNotNull);
  });

  test('ролики пришли — молчим', () {
    final w = watch()..ids = 6;
    expect(w.check(t0.add(const Duration(minutes: 2)), proxyOn: false, blocked: false), isNull);
  });

  test('25 секунд ещё не прошло — рано', () {
    expect(watch().check(t0.add(const Duration(seconds: 20)), proxyOn: false, blocked: null), isNull);
  });

  test('за одну ленту отчёт уходит один раз', () {
    final w = watch();
    expect(w.check(t0.add(const Duration(seconds: 30)), proxyOn: false, blocked: null), isNotNull);
    expect(w.check(t0.add(const Duration(seconds: 60)), proxyOn: false, blocked: null), isNull);
  });

  test('сбой включения прокси попадает в отчёт', () {
    final r = watch().check(t0.add(const Duration(seconds: 30)),
        proxyOn: false, blocked: true, proxyError: 'unsupported on iOS 16');
    expect(r!['proxy_error'], 'unsupported on iOS 16');
  });
}
