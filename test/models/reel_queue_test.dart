import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/reel_queue.dart';

void main() {
  test('номера из ответа платформы — по порядку и без повторов', () {
    const text = '{"a":{"videoId":"AAAAAAAAAAA"},"b":[{"videoId":"BBBBBBBBB-_"},{"videoId":"AAAAAAAAAAA"}],"c":"videoId"}';
    expect(ReelQueue.idsIn(text), ['AAAAAAAAAAA', 'BBBBBBBBB-_']);
  });

  test('показанный ролик второй раз в очередь не встаёт', () {
    final q = ReelQueue();
    expect(q.add(['AAAAAAAAAAA', 'BBBBBBBBBBB']), 2);
    expect(q.take(1), ['AAAAAAAAAAA']);
    expect(q.add(['AAAAAAAAAAA', 'CCCCCCCCCCC']), 1);
    expect(q.take(5), ['BBBBBBBBBBB', 'CCCCCCCCCCC']);
  });

  test('номера всех площадок проходят', () {
    expect(ReelQueue.isId('xRvQVFXrS90'), isTrue); // Shorts
    expect(ReelQueue.isId('7654645616496168200'), isTrue); // TikTok
    expect(ReelQueue.isId('1ee26921edb653d7c94c65f9281ad20e'), isTrue); // Rutube
    expect(ReelQueue.isId('-232619944_456249468_c1df4e96a6eb1a50'), isTrue); // ВК
    expect(ReelQueue.isId('oo1uG6cEPAAA'), isTrue); // Дзен
    expect(ReelQueue.isId('https://evil'), isFalse);
  });

  test('мусор и чужие форматы отбрасываются', () {
    final q = ReelQueue();
    expect(q.add(['short', 12, null, 'AAAAAAAAAAA?', 'AAAAAAAAAAA']), 1);
  });

  test('ролик из ленты партнёра вычёркивается и у нас', () {
    final q = ReelQueue()..add(['AAAAAAAAAAA', 'BBBBBBBBBBB']);
    q.markShown('AAAAAAAAAAA');
    expect(q.take(5), ['BBBBBBBBBBB']);
    expect(q.add(['AAAAAAAAAAA']), 0);
  });

  test('обновление выбрасывает запас, но просмотренное не возвращает', () {
    final q = ReelQueue()..add(['AAAAAAAAAAA', 'BBBBBBBBBBB']);
    q.take(1);
    q.dropPending();
    expect(q.length, 0);
    // Показанный не вернётся, а невиденный из сброшенного может прийти снова.
    expect(q.add(['AAAAAAAAAAA', 'BBBBBBBBBBB', 'CCCCCCCCCCC']), 2);
  });

  test('запас не растёт без конца', () {
    final q = ReelQueue(limit: 3);
    q.add(List.generate(10, (i) => 'A' * 10 + '$i'));
    expect(q.length, 3);
    expect(q.last, 'AAAAAAAAAA2');
  });
}
