/// Что снимет отмена: последний штрих, последнюю правку формы или последнее
/// стирание линии целиком.
///
/// На холсте разные действия делят одну кнопку «отменить». Нарисованные
/// штрихи лежат своим стеком, правки выделенной фигуры — своим, стёртые
/// целиком линии — своим, и без общей шкалы отмена сняла бы сперва все штрихи
/// и только потом добралась до перемещённого круга — то есть снесла бы
/// работу, которую человек трогать не просил.
///
/// Шкала — сквозной счётчик действий: у кого номер больше, тот и случился
/// позже. Отсутствие действия обозначается `null`.
enum UndoTarget { stroke, edit, erase }

UndoTarget? undoTarget({int? strokeSeq, int? editSeq, int? eraseSeq}) {
  UndoTarget? best;
  var bestSeq = -1;
  for (final (target, seq) in [
    (UndoTarget.stroke, strokeSeq),
    (UndoTarget.edit, editSeq),
    (UndoTarget.erase, eraseSeq),
  ]) {
    if (seq != null && seq > bestSeq) {
      best = target;
      bestSeq = seq;
    }
  }
  return best;
}
