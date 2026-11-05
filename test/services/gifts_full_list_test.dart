// Полка «Что дарили» считает все подарки, а не первую страницу.
//
// До 05.11.2026 `fetchGiftsFor` брал `perPage: 200`, и у пары с большим
// числом подарков счёт застывал на 200 (обращение 591). Сторож по исходнику:
// в теле функции не должно быть постраничной выборки.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fetchGiftsFor берёт все подарки', () {
    final src = File('lib/services/pb_data_service.dart').readAsStringSync();
    final start = src.indexOf('Future<List<Map<String, dynamic>>> fetchGiftsFor(');
    expect(start, isNot(-1));
    final end = src.indexOf('\n  }\n', start);
    final body = src.substring(start, end);
    expect(body, contains('getFullList('));
    expect(body, isNot(contains('perPage')));
  });
}
