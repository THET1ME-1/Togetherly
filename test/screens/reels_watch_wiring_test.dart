import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Отчёт о застрявшей ленте работает, только пока его кормят: скрытая
/// страница считает загрузки и номера, а комната через 25 секунд шлёт
/// событие. Отвалится одно звено — лента снова будет висеть молча.
void main() {
  final feed = File('lib/services/reels/reels_feed.dart').readAsStringSync();
  final room = File('lib/screens/together/watch_room_screen.dart').readAsStringSync();

  test('скрытая страница пишет загрузки, отказы и номера', () {
    expect(feed, contains('onLoadStop:'));
    expect(feed, contains('onReceivedError:'));
    expect(feed, contains('onReceivedHttpError:'));
    expect(feed, contains('watch?.heard += ids.length'));
    expect(feed, contains('watch?.ids += added'));
  });

  test('комната отдаёт ленте учёт и шлёт отчёт', () {
    expect(room, contains('watch: watch'));
    expect(room, contains('ReelsTelemetry.stalled('));
    expect(room, contains('proxyError: ReelsProxy.lastError'));
    expect(room, contains('_reelsStall?.cancel()'));
  });
}
