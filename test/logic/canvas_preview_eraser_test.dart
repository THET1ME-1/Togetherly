import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/canvas_meta.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/widgets/draw/canvas_preview.dart';

/// Плитка холста рисуется не из снимка, а из штрихов, и slice по первым
/// полутора тысячам возвращал на неё всё стёртое: мазки в slice попадали, а
/// ластик, который их снимает, шёл позже и отбрасывался. Жалоба в Google Play
/// 06.09.2026: «всё что я стирал тоже остаётся, когда смотришь готовый
/// рисунок».
void main() {
  DrawStroke stroke(int order, {bool eraser = false}) => DrawStroke(
        id: 's$order',
        userId: 'u',
        colorValue: 0xFF000000,
        strokeWidth: 4,
        points: const [DrawPoint(0.1, 0.1), DrawPoint(0.9, 0.9)],
        isEraser: eraser,
        orderIndex: order,
      );

  final meta = CanvasMeta(
    id: 'c1',
    name: 'Холст',
    createdAt: DateTime(2026, 9, 11),
    updatedAt: DateTime(2026, 9, 11),
  );

  List<DrawStroke> visible(List<DrawStroke> all) =>
      CanvasPreviewPainter(strokes: all, meta: meta).visibleStrokes;

  test('короткий холст рисуется целиком', () {
    final all = List.generate(40, (i) => stroke(i));
    expect(visible(all).length, 40);
  });

  test('длинный холст без ластика режется по прежнему пределу', () {
    final all = List.generate(kPreviewStrokeLimit + 500, (i) => stroke(i));
    expect(visible(all).length, kPreviewStrokeLimit);
  });

  test('ластик за пределом sliceа попадает в плитку вместе со стёртым', () {
    final all = [
      ...List.generate(kPreviewStrokeLimit + 200, (i) => stroke(i)),
      stroke(kPreviewStrokeLimit + 200, eraser: true),
      ...List.generate(50, (i) => stroke(kPreviewStrokeLimit + 201 + i)),
    ];
    final slice = visible(all);
    expect(slice.any((s) => s.isEraser), isTrue,
        reason: 'без ластика стёртое остаётся на плитке');
    expect(slice.length, kPreviewStrokeLimit + 201);
  });

  test('последний ластик важнее первого: slice тянется до него', () {
    final all = [
      ...List.generate(kPreviewStrokeLimit + 10, (i) => stroke(i)),
      stroke(kPreviewStrokeLimit + 10, eraser: true),
      ...List.generate(300, (i) => stroke(kPreviewStrokeLimit + 11 + i)),
      stroke(kPreviewStrokeLimit + 311, eraser: true),
      ...List.generate(5, (i) => stroke(kPreviewStrokeLimit + 312 + i)),
    ];
    expect(visible(all).length, kPreviewStrokeLimit + 312);
  });

  test('холст на сто тысяч штрихов не тянет плитку целиком', () {
    final all = [
      ...List.generate(kPreviewEraserLimit + 5000, (i) => stroke(i)),
    ];
    all[kPreviewEraserLimit + 4000] = stroke(kPreviewEraserLimit + 4000, eraser: true);
    expect(visible(all).length, kPreviewStrokeLimit,
        reason: 'ластик за потолком плитку не удлиняет');
  });
}
