import 'dart:math' as math;

import 'draw_stroke.dart';

/// Повтор рисования: холст умеет показать, как рисунок появлялся.
///
/// Записывать ничего не надо — порядок мазков уже лежит в базе
/// (`order_index`), и повтор это просто прокрутка списка. Отсюда и мера
/// времени: не секунды и не штрихи, а ТОЧКИ. Длинная дуга рисуется дольше
/// короткой чёрточки, как оно и было под рукой.

/// Штрихи, нарисованные к моменту, когда показано [points] точек.
///
/// Последний мазок отдаётся обрезанным — он и есть тот, что рисуется прямо
/// сейчас. Фигура обрезке не поддаётся: у неё две точки, и половина фигуры
/// это не половина рисунка, а мусор.
List<DrawStroke> strokesUpTo(List<DrawStroke> all, int points) {
  if (points <= 0) return const [];
  final out = <DrawStroke>[];
  var left = points;
  for (final s in all) {
    final count = s.points.length;
    if (left >= count) {
      out.add(s);
      left -= count;
      continue;
    }
    // Картинке и фигуре расти неоткуда: либо есть, либо нет.
    if (s.shapeType != null || s.imageUrl != null) {
      if (left > 0) out.add(s);
      return out;
    }
    // Одна точка — это ещё не линия: мазок начинает показываться со второй,
    // иначе перед каждым появляется вспышка-точка.
    if (left >= 2) {
      out.add(
        DrawStroke(
          id: s.id,
          clientId: s.clientId,
          userId: s.userId,
          colorValue: s.colorValue,
          strokeWidth: s.strokeWidth,
          points: s.points.sublist(0, left),
          isEraser: s.isEraser,
          isFilledShape: s.isFilledShape,
          shapeType: s.shapeType,
          orderIndex: s.orderIndex,
          layer: s.layer,
        ),
      );
    }
    return out;
  }
  return out;
}

/// Сколько всего точек в рисунке — знаменатель прокрутки.
int totalReplayPoints(List<DrawStroke> all) {
  var sum = 0;
  for (final s in all) {
    sum += s.points.length;
  }
  return sum;
}

/// Сколько длится показ. Короткий рисунок не мельтешит, длинный не тянется
/// десять минут: скорость плавает, а не число мазков в секунду.
Duration replayDuration(int points) {
  const perSecond = 900; // точек в секунду на длинном рисунке
  final seconds = math.max(1.5, math.min(60.0, points / perSecond));
  return Duration(milliseconds: (seconds * 1000).round());
}
