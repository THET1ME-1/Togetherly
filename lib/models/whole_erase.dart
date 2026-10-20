import 'dart:ui';

import 'draw_stroke.dart';
import 'stroke_transform.dart';

/// Ластик «Линия целиком»: касание убирает задетый мазок полностью.
///
/// Берутся только линии и фигуры текущего слоя. Картинку (фото, заливку
/// ведром) так стереть нельзя — её правит свой инструмент, и случайный
/// мазок по снимку не должен его уносить. Мазок-ластик тоже не берём: убрать
/// его — значит вернуть стёртую им краску, и человек увидел бы, что ластик
/// «рисует». Мазки партнёра в полёте (`live_…`) ещё не записаны в базу, удалять
/// там нечего.
List<DrawStroke> strokesUnderFinger(
  List<DrawStroke> strokes,
  Offset point,
  Size canvas, {
  required int layer,
  double reach = 12,
  Set<String> skip = const {},
}) =>
    [
      for (final s in strokes)
        if (s.layer == layer &&
            !s.isImageStroke &&
            !s.isEraser &&
            !s.id.startsWith('live_') &&
            !skip.contains(s.id) &&
            strokeHitAt(s, point, canvas, tolerance: reach))
          s,
    ];

/// Вставка с прижатием индекса к длине списка: история отмены могла
/// укоротиться, пока линия лежала стёртой.
List<String> insertAt(List<String> ids, int index, String id) =>
    [...ids]..insert(index.clamp(0, ids.length), id);

/// Стёртый целиком мазок и его место в истории отмены.
class ErasedStroke {
  const ErasedStroke({
    required this.stroke,
    this.ownIndex,
    this.ownSeq,
    this.mirrorGroup,
  });

  final DrawStroke stroke;

  /// Своё: место мазка в стеке отмены и номер по общей шкале. У мазка
  /// партнёра обоих нет — отменять его рисование мы не можем.
  final int? ownIndex;
  final int? ownSeq;

  /// Зеркальная пачка, если мазок из неё.
  final String? mirrorGroup;
}

/// Одно движение ластика «Линия целиком» — одна отмена.
class WholeErase {
  WholeErase(this.seq);

  /// Номер по общей шкале действий холста.
  int seq;

  final List<ErasedStroke> strokes = [];

  /// Идентификаторы, под которыми мазки вернулись при отмене: возврат
  /// стирания убирает именно их.
  final List<String> restoredIds = [];
}
