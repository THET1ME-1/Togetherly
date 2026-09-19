// Телефон помнит, какие файлы уже лежат в галерее: второе «Сохранить всё» не
// должно плодить копии, а кнопка показывает, сколько осталось.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_media.dart';
import 'package:love_app/services/saved_media_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaFile _f(String ref, [int i = 0]) =>
    MediaFile(ref: ref, kind: SaveKind.photo, index: i);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('сохранённое переживает перезапуск', () async {
    final a = SavedMediaLedger.forTest();
    await a.load();
    await a.add('pb://media/a/1.webp');

    final b = SavedMediaLedger.forTest();
    await b.load();
    expect(b.contains('pb://media/a/1.webp'), isTrue);
    expect(b.contains('pb://media/a/2.webp'), isFalse);
  });

  test('pending отдаёт то, чего ещё нет в галерее, по ключу файла', () async {
    final l = SavedMediaLedger.forTest();
    await l.load();
    await l.add('pb://media/a/1.webp');
    final files = [
      _f('https://togetherly.day/api/files/media/a/1.webp?token=t', 0),
      _f('pb://media/a/2.webp', 1),
    ];
    expect(l.pending(files).map((f) => f.index), [1]);
    expect(l.countSaved(files), 1);
  });

  test('журнал ограничен: самое старое вытесняется', () async {
    final l = SavedMediaLedger.forTest(limit: 3);
    await l.load();
    for (var i = 0; i < 5; i++) {
      await l.add('k$i');
    }
    expect(l.contains('k0'), isFalse);
    expect(l.contains('k1'), isFalse);
    expect(l.contains('k4'), isTrue);

    final again = SavedMediaLedger.forTest(limit: 3);
    await again.load();
    expect(again.contains('k2'), isTrue);
    expect(again.contains('k1'), isFalse);
  });

  test('повторное добавление поднимает ключ в свежие', () async {
    final l = SavedMediaLedger.forTest(limit: 2);
    await l.load();
    await l.add('a');
    await l.add('b');
    await l.add('a');
    await l.add('c');
    expect(l.contains('a'), isTrue);
    expect(l.contains('b'), isFalse);
  });
}
