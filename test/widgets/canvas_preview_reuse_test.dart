import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/canvas_meta.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/widgets/draw/canvas_preview.dart';

/// Плитка галереи не показывает рисунок удалённого холста (TOG-12).
///
/// Повторено на эмуляторе 22.10.2026: партнёр удалил «Canvas 3», галерея
/// убрала его, «Canvas 2» встал на его место — и показал рисунок «Canvas 3».
/// Плитка без ключа переиспользуется для другого холста, а штрихи прежнего
/// приходили с сервера позже своих и затирали их. Удаление выглядело так,
/// будто не сработало.
DrawStroke _line(String id, double y) => DrawStroke(
      id: id,
      clientId: id,
      userId: 'me',
      colorValue: 0xFF2255FF,
      strokeWidth: 6,
      points: [DrawPoint(0.1, y), DrawPoint(0.9, y)],
      orderIndex: 1,
    );

CanvasMeta _meta(String id) => CanvasMeta(
      id: id,
      name: id,
      createdAt: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 10, 20),
    );

Widget _tile(CanvasMeta meta) => MaterialApp(
      home: SizedBox(
        width: 160,
        height: 200,
        child: CanvasPreview(
          meta: meta,
          uid: 'me',
          groupId: 'g1',
          placeholder: const SizedBox.expand(),
        ),
      ),
    );

void main() {
  testWidgets('штрихи прежнего холста, пришедшие поздно, не занимают плитку',
      (tester) async {
    final deleted = _line('rdeleted0000001', 0.3);
    final kept = _line('rkept0000000001', 0.7);
    // Свой холст на диске — он грузится сразу; удалённый тянется с сервера.
    SharedPreferences.setMockInitialValues({
      'strokes_v1_me_g1_canvas_kept':
          jsonEncode([{'id': kept.id, ...kept.toFirestore()}]),
    });
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final body = {
          'page': 1,
          'perPage': 400,
          'totalItems': 1,
          'totalPages': 1,
          'items': [
            {
              'id': deleted.id,
              'collectionName': 'canvas_strokes',
              'group_id': 'g1',
              'canvas_id': 'canvas_deleted',
              'order_index': 1,
              'data': deleted.toFirestore(),
            },
          ],
        };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
            headers: {'content-type': 'application/json'});
      }),
    ));

    await tester.pumpWidget(_tile(_meta('canvas_deleted')));
    // Холст удалили, на месте плитки теперь соседний.
    await tester.pumpWidget(_tile(_meta('canvas_kept')));
    // Ответ сервера по удалённому холсту приходит позже своих штрихов.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final paint = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(CanvasPreview), matching: find.byType(CustomPaint)));
    final painter = paint.painter! as CanvasPreviewPainter;
    expect(painter.strokes.map((s) => s.id), [kept.id],
        reason: 'Плитка показывает свой холст, а не удалённый');
  });
}
