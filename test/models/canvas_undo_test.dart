import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/canvas_undo.dart';
import 'package:love_app/models/draw_stroke.dart';

DrawStroke _s(String id, String user, int order, {int layer = 0}) => DrawStroke(
      id: id,
      userId: user,
      colorValue: 0xFF000000,
      strokeWidth: 4,
      points: const [],
      orderIndex: order,
      layer: layer,
    );

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

  // Обращение 403 (1.38.0, общая раскраска): «Отменить» горит, а нажатие не
  // делает ничего. На общем холсте свой штрих после записи на сервере меняет
  // временный id на серверный; номер действия лежал под старым, отмена не
  // находила его и молча выходила.
  group('свой штрих сменил id', () {
    test('номер действия и группа зеркала переезжают под новый id', () {
      final seqs = {'local_1': 5, 'local_2': 6};
      final mirror = {'local_1': 'm1'};
      adoptStrokeId(seqs, mirror, from: 'local_1', to: 'srv_1');
      expect(seqs, {'srv_1': 5, 'local_2': 6});
      expect(mirror, {'srv_1': 'm1'});
    });

    test('после смены id отмена снимает этот штрих', () {
      final seqs = {'local_1': 5};
      adoptStrokeId(seqs, {}, from: 'local_1', to: 'srv_1');
      expect(undoTarget(strokeSeq: ownStrokeSeq(seqs, 'srv_1')), UndoTarget.stroke);
    });
  });

  test('свой штрих без номера (загружен с диска) всё равно отменяется', () {
    expect(undoTarget(strokeSeq: ownStrokeSeq(const {}, 'old')), UndoTarget.stroke);
  });

  // Владелец, 21.10.2026: «почему не сделать отмену» линий прошлого захода.
  // Одиночный холст поднимал их в историю, общий начинал с пустой.
  test('общий холст: в историю отмены встают свои линии по порядку рисования', () {
    final strokes = [
      _s('b', 'me', 3, layer: 1),
      _s('p', 'partner', 2),
      _s('a', 'me', 1),
      _s('c', 'me', 5),
    ];
    expect(ownStrokeHistory(strokes, 'me'), ['a', 'b', 'c'],
        reason: 'отмена идёт от последнего нарисованного, слой тут ни при чём');
  });

  test('свой штрих без номера старше любой правки этого захода', () {
    expect(
        undoTarget(strokeSeq: ownStrokeSeq(const {}, 'old'), editSeq: 1),
        UndoTarget.edit);
  });
}
