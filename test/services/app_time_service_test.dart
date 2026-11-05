// Служба часов в приложении: несданное переживает перезапуск, сервер —
// источник правды, сбой сети ничего не теряет (план 2026-11-05-ranks-by-hours).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/app_time_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 11, 5, 12);

  late List<Map<String, dynamic>> calls;
  Map<String, dynamic>? Function(Map<String, dynamic>) answer = (_) => null;

  AppTimeService make(DateTime Function() clock) {
    final s = AppTimeService.forTest()
      ..now = clock
      ..send = (path, body) async {
        calls.add({'path': path, ...body});
        return answer(body);
      };
    return s;
  }

  // Запуск как в приложении: первая отправка дошла, приложение на экране.
  Future<void> open(AppTimeService s) async {
    await s.start();
    await pumpEventQueue();
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    answer = (_) => null;
  });

  test('несданное переживает перезапуск', () async {
    var t = t0;
    final a = make(() => t);
    await open(a);
    t = t0.add(const Duration(seconds: 90));
    a.didChangeAppLifecycleState(AppLifecycleState.paused); // сервер молчит
    await pumpEventQueue();
    a.stop();
    final b = make(() => t);
    await b.start();
    expect(b.counter.pendingSeconds, 90);
    b.stop();
  });

  test('принятое сервером вычитается, часы берутся из ответа', () async {
    var t = t0;
    final s = make(() => t);
    answer = (body) => {
      'ok': true,
      'seconds': 5000 + (body['seconds'] as int),
      'granted': body['seconds'],
      'rank_seen': 2,
    };
    await open(s);
    t = t0.add(const Duration(seconds: 120));
    await s.flush();
    expect(s.counter.pendingSeconds, 0);
    expect(s.seconds.value, 5120);
    expect(s.rankSeen, 2);
    expect(calls.last['device'], isNotEmpty);
    s.stop();
  });

  test('сервер засчитал меньше — остаток ждёт, но не больше часа', () async {
    var t = t0;
    final s = make(() => t);
    answer = (_) => {'ok': true, 'seconds': 30, 'granted': 30, 'rank_seen': -1};
    s.counter.restore(5000);
    await open(s);
    expect(s.counter.pendingSeconds, 3600);
    s.stop();
  });

  test('отметка звания только растёт', () async {
    final s = make(() => t0);
    await open(s);
    await s.markSeen(4);
    await s.markSeen(2);
    expect(s.rankSeen, 4);
    expect(
      calls.where((c) => c['path'] == '/api/user/app-time/seen').length,
      1,
    );
    s.stop();
  });

  test('пороги с сервера: мусор — запасные', () {
    final s = make(() => t0)..ingestHours([0, 1]);
    expect(s.hours.length, 14);
  });
}
