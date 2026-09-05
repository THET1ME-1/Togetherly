// Оригинал снимка в контейнер виджета попадать не должен НИКОГДА.
//
// Расширению виджета на iPhone отводят около 30 МБ, снимок с камеры 4000×3000
// в разжатом виде занимает под пятьдесят — систему это заставляет убить
// расширение до отрисовки, и человек видит пустоту. На Android большой битмап
// не проходит через Binder в RemoteViews с тем же исходом.
//
// А запасной путь сжатия делал ровно это: «пустой ответ кодека — отдаём
// исходник, лучше большой, чем никакой» и `catch (e) { return bytes; }`. После
// 04.09.2026 туда стало попадать заметно больше людей: тогда на кодек повесили
// предел в 20 секунд, и на медленных телефонах он срабатывает.
//
// Правило: в виджет идёт только то, что влезает в предел. Не ужалось — не
// кладём вовсе, пусть на столе останется прежний снимок.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_image_limit.dart';

Uint8List bytes(int n) => Uint8List(n);

void main() {
  test('ужатое в пределах — берём его', () {
    final out = widgetPhotoPayload(original: bytes(9000000), compressed: bytes(180000));
    expect(out, isNotNull);
    expect(out!.length, 180000);
  });

  test('кодек молчит — оригинал не кладём', () {
    expect(widgetPhotoPayload(original: bytes(9000000), compressed: null), isNull);
  });

  test('кодек вернул пустоту — оригинал не кладём', () {
    expect(widgetPhotoPayload(original: bytes(9000000), compressed: bytes(0)), isNull);
  });

  test('ужатое всё ещё огромное — не кладём', () {
    final out = widgetPhotoPayload(
      original: bytes(9000000),
      compressed: bytes(kMaxWidgetPhotoBytes + 1),
    );
    expect(out, isNull);
  });

  test('маленький оригинал проходит и без сжатия', () {
    final small = bytes(40000);
    final out = widgetPhotoPayload(original: small, compressed: null);
    expect(out, isNotNull);
    expect(out!.length, 40000);
  });

  test('предел не больше того, что переваривает виджет', () {
    expect(kMaxWidgetPhotoBytes, lessThanOrEqualTo(2 * 1024 * 1024));
  });
}
