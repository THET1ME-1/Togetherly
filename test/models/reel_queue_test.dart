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

  test('запас не растёт без конца', () {
    final q = ReelQueue(limit: 3);
    q.add(List.generate(10, (i) => 'A' * 10 + '$i'));
    expect(q.length, 3);
    expect(q.last, 'AAAAAAAAAA2');
  });
}
