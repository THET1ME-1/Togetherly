import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/canvas_undo.dart';

/// Кнопка «отменить» на холсте одна, а действий два: нарисовать штрих и
/// подвинуть уже нарисованное. Снимать надо последнее по времени.
void main() {
  test('правка свежее штриха — снимаем правку', () {
    expect(undoTakesEdit(lastEditSeq: 7, lastStrokeSeq: 3), isTrue);
  });

  test('штрих свежее правки — снимаем штрих', () {
    expect(undoTakesEdit(lastEditSeq: 3, lastStrokeSeq: 7), isFalse);
  });

  test('правок не было — снимаем штрих', () {
    expect(undoTakesEdit(lastEditSeq: null, lastStrokeSeq: 2), isFalse);
  });

  test('штрихов не было — снимаем правку', () {
    expect(undoTakesEdit(lastEditSeq: 2, lastStrokeSeq: null), isTrue);
  });

  test('пусто с обеих сторон — отменять нечего', () {
    expect(undoTakesEdit(lastEditSeq: null, lastStrokeSeq: null), isFalse);
  });
}
