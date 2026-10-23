import 'package:flutter_test/flutter_test.dart';

import 'package:love_app/models/stroke_record_id.dart';

/// Id записи штриха считает телефон, а не сервер (TOG-12, 22.10.2026).
///
/// Пока id выдавал сервер, повтор создания после таймаута или 502 заводил
/// вторую запись того же мазка: на раскрасках с 19 по 22 октября нашлось 187
/// штрихов в 2–12 копиях. Ластик и отмена снимали одну копию, остальные
/// оставались на холсте, и стёртое «возвращалось».
void main() {
  test('один и тот же мазок даёт один и тот же id', () {
    expect(
      strokeRecordId('rgroup', 'canvas_1', 'local_1_2_abcd'),
      strokeRecordId('rgroup', 'canvas_1', 'local_1_2_abcd'),
    );
  });

  test('id подходит под маску PocketBase: 15 знаков a-z0-9', () {
    final id = strokeRecordId('r5269c54ac34919', 'canvas_1792428975321',
        'local_1792630961924_57_x9k2');
    expect(id, matches(RegExp(r'^[a-z0-9]{15}$')));
  });

  test('разные мазки, холсты и пары дают разные id', () {
    final ids = {
      strokeRecordId('g1', 'c1', 'local_1_1_aaaa'),
      strokeRecordId('g1', 'c1', 'local_1_2_aaaa'),
      strokeRecordId('g1', 'c2', 'local_1_1_aaaa'),
      strokeRecordId('g2', 'c1', 'local_1_1_aaaa'),
    };
    expect(ids, hasLength(4));
  });

  test('isStrokeRecordId узнаёт только id записи, а не номер мазка', () {
    expect(isStrokeRecordId(strokeRecordId('g', 'c', 'local_1_1_a')), isTrue);
    expect(isStrokeRecordId('local_1792630961924_57_x9k2'), isFalse);
    expect(isStrokeRecordId('fill_1792630961924_57'), isFalse);
    expect(isStrokeRecordId(''), isFalse);
  });
}
