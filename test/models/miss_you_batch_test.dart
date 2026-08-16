import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/miss_you_batch.dart';

void main() {
  group('MissYouBatch', () {
    test('одиночное нажатие уходит как есть', () {
      final batch = MissYouBatch();
      expect(batch.add(), 1);
      expect(batch.take(), 1);
    });

    test('серия нажатий копится в одну отправку', () {
      // На iPhone половина нажатий пропадала: каждый тап уходил своим
      // запросом, а сервер отбивал их лимитом (523 отказа 429 за сутки).
      // Копим и шлём одним числом.
      final batch = MissYouBatch();
      for (var i = 0; i < 7; i++) {
        batch.add();
      }
      expect(batch.take(), 7);
      expect(batch.take(), 0, reason: 'после отправки счётчик обнуляется');
    });

    test('счётчик не разрастается без предела', () {
      // Двадцать за раз — потолок роута: дальше это уже не «скучаю», а спам.
      final batch = MissYouBatch();
      for (var i = 0; i < 50; i++) {
        batch.add();
      }
      expect(batch.take(), MissYouBatch.maxPerSend);
    });

    test('нажатия сверх предела не теряются, а уходят следующей отправкой', () {
      final batch = MissYouBatch();
      for (var i = 0; i < MissYouBatch.maxPerSend + 5; i++) {
        batch.add();
      }
      expect(batch.take(), MissYouBatch.maxPerSend);
      expect(batch.take(), 5);
    });

    test('пустой накопитель отдаёт ноль', () {
      expect(MissYouBatch().take(), 0);
    });

    test('отправка возвращает нажатия обратно, если не дошла', () {
      final batch = MissYouBatch();
      batch.add();
      batch.add();
      final sent = batch.take();
      batch.giveBack(sent);
      expect(batch.take(), 2);
    });

    test('уходя, накопитель отдаёт ВСЁ, а не первые двадцать', () {
      // Жалоба со скринкастом 16.08.2026: «огромные проблемы со счётчиком».
      // На записи человек натыкал до 6687, свернул приложение — и увидел 6670.
      // Семнадцать нажатий не уехали никуда: экран закрывался, а `take()`
      // отдаёт не больше двадцати за раз, и остаток оставался в памяти.
      final batch = MissYouBatch();
      for (var i = 0; i < 37; i++) {
        batch.add();
      }
      expect(batch.takeAllChunks(), [20, 17]);
      expect(batch.pending, 0, reason: 'в накопителе не должно остаться ничего');
    });

    test('пустой накопитель на выходе не шлёт ничего', () {
      expect(MissYouBatch().takeAllChunks(), isEmpty);
    });

    test('ровно двадцать уходят одной пачкой', () {
      final batch = MissYouBatch();
      for (var i = 0; i < 20; i++) {
        batch.add();
      }
      expect(batch.takeAllChunks(), [20]);
    });
  });
}
