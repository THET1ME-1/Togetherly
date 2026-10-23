import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/stroke_record_id.dart';
import 'package:love_app/services/canvas_repository.dart';
import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// Повтор создания штриха не заводит вторую запись (TOG-12, 22.10.2026).
///
/// Очередь считает операцию проваленной по своему таймауту (20 с) и по 502, а
/// запрос к этому моменту уже мог дойти до базы. Пока id штриха выдавал
/// сервер, каждый повтор заводил новую копию: на одном холсте 56 мазков лежали
/// по 12 раз. Теперь id считает телефон, и повтор упирается в «уже есть».
http.Response _json(Object body, int code) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Сервер штрихов: хранит записи по id, первое создание записывает, но
/// отвечает 502 — как точка входа, у которой упал рабочий процесс hotpath.
class _StrokeServer {
  final Map<String, Map<String, dynamic>> records = {};
  final List<Map<String, dynamic>> posts = [];
  bool loseFirstAnswer = true;
  int _gen = 0;

  Future<http.Response> handle(http.Request req) async {
    if (req.method == 'POST' &&
        req.url.path == '/api/collections/canvas_strokes/records') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      posts.add(body);
      final id = (body['id'] as String?) ??
          'gen${(_gen++).toString().padLeft(12, '0')}';
      if (records.containsKey(id)) {
        return _json({
          'code': 400,
          'message': 'Failed to create record.',
          'data': {
            'id': {
              'code': 'validation_not_unique',
              'message': 'Value must be unique.',
            },
          },
        }, 400);
      }
      records[id] = {
        ...body,
        'id': id,
        'collectionId': 'canvas_strokes',
        'collectionName': 'canvas_strokes',
      };
      if (loseFirstAnswer) {
        loseFirstAnswer = false;
        return _json({'code': 502, 'message': 'Bad Gateway', 'data': {}}, 502);
      }
      return _json(records[id]!, 200);
    }
    return _json(
        {'code': 404, 'message': "The requested resource wasn't found.", 'data': {}},
        404);
  }
}

DrawStroke _stroke(String clientId) => DrawStroke(
      id: clientId,
      clientId: clientId,
      userId: 'me',
      colorValue: 0xFF112233,
      strokeWidth: 4,
      points: const [DrawPoint(0.1, 0.1), DrawPoint(0.2, 0.2)],
      orderIndex: 7,
    );

Future<void> _drain(OutboxService ob) async {
  for (var i = 0; i < 40; i++) {
    if (ob.pendingCount.value == 0) return;
    await ob.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late OutboxService ob;
  late _StrokeServer server;

  setUp(() async {
    await LocalStore.instance
        .initWith(databaseFactoryMemory, 'stroke_add_idempotent.db');
    ob = OutboxService.instance;
    await ob.clear();
    server = _StrokeServer();
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient(server.handle),
    ));
  });

  test('повтор из очереди после 502 не заводит вторую копию мазка', () async {
    const clientId = 'local_1792630961924_57_x9k2';
    final recordId = strokeRecordId('g1', 'c1', clientId);
    await ob.enqueue('strokeAdd', {
      'id': recordId,
      'groupId': 'g1',
      'canvasId': 'c1',
      'stroke': _stroke(clientId).toFirestore(),
    });
    await _drain(ob);

    expect(server.posts.length, greaterThanOrEqualTo(2),
        reason: 'Первый ответ потерян — очередь обязана повторить');
    expect(server.records, hasLength(1),
        reason: 'Повтор упирается в «уже есть», а не заводит копию');
    expect(server.records.keys.single, recordId);
    expect(ob.pendingCount.value, 0,
        reason: '«Уже есть» — это успех, а не «Не сохранилось»');
  });

  test('операция из старой версии без id записи создаётся как раньше', () async {
    server.loseFirstAnswer = false;
    await ob.enqueue('strokeAdd', {
      'id': 'local_1792630961924_57_x9k2',
      'groupId': 'g1',
      'canvasId': 'c1',
      'stroke': _stroke('local_1792630961924_57_x9k2').toFirestore(),
    });
    await _drain(ob);

    expect(server.records, hasLength(1));
    expect(server.posts.single.containsKey('id'), isFalse,
        reason: 'Номер мазка не годится в id записи — его выдаёт сервер');
    expect(ob.pendingCount.value, 0);
  });

  test('две выгрузки подряд не отправляют одну операцию дважды', () async {
    // Флаг «уже выгружаю» ставился только после await базы, и два вызова
    // flush() подряд (enqueue зовёт его сам) проходили проверку оба. Так одна
    // операция уходила дважды: у мазка без id записи это две копии.
    server.loseFirstAnswer = false;
    await ob.enqueue('strokeAdd', {
      'id': 'local_1792630961924_59_x9k2',
      'groupId': 'g1',
      'canvasId': 'c1',
      'stroke': _stroke('local_1792630961924_59_x9k2').toFirestore(),
    });
    await Future.wait([ob.flush(), ob.flush()]);
    await _drain(ob);

    expect(server.posts, hasLength(1));
    expect(server.records, hasLength(1));
  });

  test('экран: создание с id, которое уже есть на сервере, — успех', () async {
    server.loseFirstAnswer = false;
    const clientId = 'local_1792630961924_58_x9k2';
    final recordId = strokeRecordId('g1', 'c1', clientId);
    final repo = CanvasRepository();
    final data = _stroke(clientId).toFirestore();

    expect(await repo.addStroke('g1', 'c1', data, id: recordId), recordId);
    expect(await repo.addStroke('g1', 'c1', data, id: recordId), recordId,
        reason: 'Второй ответ «уже есть» значит, что мазок на сервере');
    expect(server.records, hasLength(1));
  });
}
