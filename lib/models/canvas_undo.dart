import 'draw_stroke.dart';

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

/// История отмены общего холста при открытии: свои линии по порядку
/// рисования, от старых к новым. Одиночный холст поднимал их с диска всегда,
/// общий начинал с пустой истории, и линию прошлого захода было не отменить.
/// Порядок — по `orderIndex`, а не по слою: отменяется последнее нарисованное.
List<String> ownStrokeHistory(Iterable<DrawStroke> strokes, String uid) {
  final own = [
    for (final s in strokes)
      if (s.userId == uid) s,
  ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  return [for (final s in own) s.id];
}

/// Номер действия своего штриха для [undoTarget].
///
/// Штрих, нарисованный в прошлый заход и поднятый с диска, номера не имеет,
/// но отменить его можно: он считается старше любого действия этого захода.
int ownStrokeSeq(Map<String, int> seqs, String id) => seqs[id] ?? 0;

/// Свой штрих сменил id: на общем холсте сервер подтвердил запись, и
/// временный номер стал серверным. Всё, что ведётся по id штриха, переезжает
/// следом — номер действия и группа зеркальных копий. Иначе отмена не найдёт
/// номер и выйдет молча при живой кнопке (обращение 403, 1.38.0).
void adoptStrokeId(
  Map<String, int> seqs,
  Map<String, String> mirrorGroups, {
  required String from,
  required String to,
}) {
  if (from == to) return;
  final seq = seqs.remove(from);
  if (seq != null) seqs[to] = seq;
  final group = mirrorGroups.remove(from);
  if (group != null) mirrorGroups[to] = group;
}
