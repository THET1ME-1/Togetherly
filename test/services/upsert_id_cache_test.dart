import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/upsert_id_cache.dart';

/// Геопозиция, присутствие и «печатает» обновляются постоянно, а ищутся
/// фильтром. Без памяти о найденном id каждое обновление стоило трёх запросов —
/// поиск, отказ на создании по уникальному ключу и только потом обновление.
/// В журнале сервера это 500 отказов в час.
void main() {
  group('UpsertIdCache', () {
    test('ключ собирается из коллекции и фильтра', () {
      final a = UpsertIdCache.keyOf('live_location', 'channel="x"');
      final b = UpsertIdCache.keyOf('live_location', 'channel="y"');
      expect(a, isNot(b));
      expect(UpsertIdCache.keyOf('live_location', 'channel="x"'), a);
    });

    test('запомненный id отдаётся обратно', () {
      final cache = UpsertIdCache();
      final key = UpsertIdCache.keyOf('user_presence', 'uid="me"');
      cache.remember(key, 'rec123');
      expect(cache[key], 'rec123');
    });

    test('промах ничего не отдаёт', () {
      final cache = UpsertIdCache();
      expect(cache['неизвестный'], isNull);
    });

    test('забытый ключ пропадает — запись могли удалить', () {
      final cache = UpsertIdCache();
      const key = 'k';
      cache.remember(key, 'rec123');
      cache.forget(key);
      expect(cache[key], isNull);
    });

    test('пустые значения не запоминаются', () {
      final cache = UpsertIdCache();
      cache.remember('', 'rec');
      cache.remember('k', '');
      expect(cache.length, 0);
    });

    test('смена аккаунта чистит всё: чужие id не наши', () {
      final cache = UpsertIdCache();
      cache.remember('a', '1');
      cache.remember('b', '2');
      cache.clear();
      expect(cache.length, 0);
    });
  });
}
