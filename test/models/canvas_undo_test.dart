import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/canvas_undo.dart';

/// Кнопка «отменить» на холсте одна, а действий три: нарисовать штрих,
/// подвинуть нарисованное и стереть линию целиком. Снимать надо последнее
/// по времени.
void main() {
  test('правка свежее штриха — снимаем правку', () {
    expect(undoTarget(editSeq: 7, strokeSeq: 3), UndoTarget.edit);
  });

  test('штрих свежее правки — снимаем штрих', () {
    expect(undoTarget(editSeq: 3, strokeSeq: 7), UndoTarget.stroke);
  });

  test('правок не было — снимаем штрих', () {
    expect(undoTarget(strokeSeq: 2), UndoTarget.stroke);
  });

  test('штрихов не было — снимаем правку', () {
    expect(undoTarget(editSeq: 2), UndoTarget.edit);
  });

  test('пусто со всех сторон — отменять нечего', () {
    expect(undoTarget(), isNull);
  });

  test('стёртая целиком линия свежее всего — возвращаем её', () {
    expect(undoTarget(strokeSeq: 4, editSeq: 5, eraseSeq: 9), UndoTarget.erase);
  });

  test('после стирания нарисовали — снимаем нарисованное', () {
    expect(undoTarget(strokeSeq: 10, eraseSeq: 9), UndoTarget.stroke);
  });
}
