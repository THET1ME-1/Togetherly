import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/canvas_meta.dart';

/// Галерея рисунков перезагружает каталог на каждое realtime-событие пары, а
/// событий приходит много: правка соседнего холста, бутстрап каталога у
/// партнёра. Раньше экран на каждое из них пересобирал сетку, и миниатюры
/// моргали белым. Теперь список сравнивается по отпечатку — эти тесты стерегут
/// сравнение: пропустит лишнее изменение, и моргание вернётся.
void main() {
  CanvasMeta meta({
    String id = 'c1',
    String name = 'Холст 1',
    int updatedMs = 1000,
    String? preview,
    int? pixelW,
    int? pixelH,
  }) =>
      CanvasMeta(
        id: id,
        name: name,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
        previewBase64: preview,
        pixelW: pixelW,
        pixelH: pixelH,
      );

  group('Отпечаток холста', () {
    test('Одинаковые данные — одинаковый отпечаток', () {
      expect(meta().fingerprint, meta().fingerprint);
    });

    test('Новое превью меняет отпечаток', () {
      expect(meta(preview: 'aaaa').fingerprint,
          isNot(meta(preview: 'aaaabbbb').fingerprint));
    });

    test('Появление превью у пустого холста заметно', () {
      expect(meta().fingerprint, isNot(meta(preview: 'aaaa').fingerprint));
    });

    test('Переименование заметно', () {
      expect(meta().fingerprint, isNot(meta(name: 'Другое').fingerprint));
    });

    test('Новое время правки заметно', () {
      expect(meta().fingerprint, isNot(meta(updatedMs: 2000).fingerprint));
    });

    test('Приехавшая от партнёра сетка пикселей заметна', () {
      expect(meta().fingerprint,
          isNot(meta(pixelW: 32, pixelH: 32).fingerprint));
    });

    test('Разные холсты не путаются', () {
      expect(meta(id: 'c1').fingerprint, isNot(meta(id: 'c2').fingerprint));
    });
  });
}
