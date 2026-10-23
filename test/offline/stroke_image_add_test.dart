import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/stroke_record_id.dart';
import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// Заливка, нарисованная без сети, не пропадает (TOG-12, 22.10.2026).
///
/// Заливка ведром — это картинка: сперва файл уходит в `media`, потом штрих
/// со ссылкой на него. Раньше сбой загрузки убирал заливку с холста без
/// повтора, и в раскраске, где всё — заливки, нарисованное пропадало через
/// секунду (повторено на эмуляторе в режиме полёта). Теперь досылает очередь.
http.Response _json(Object body, int code) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _Server {
  bool mediaDown = false;
  final List<String> mediaUploads = [];
  final Map<String, Map<String, dynamic>> strokes = {};

  Future<http.Response> handle(http.BaseRequest req) async {
    final path = req.url.path;
    if (req.method == 'POST' && path == '/api/collections/media/records') {
      if (mediaDown) {
        return _json({'code': 500, 'message': 'Something went wrong.', 'data': {}}, 500);
      }
      final id = 'm${(mediaUploads.length + 1).toString().padLeft(14, '0')}';
      mediaUploads.add(id);
      return _json({
        'id': id,
        'collectionName': 'media',
        'collectionId': 'media',
        'file': 'fill_stored.png',
      }, 200);
    }
    if (req.method == 'POST' && path == '/api/collections/canvas_strokes/records') {
      final body = jsonDecode((req as http.Request).body) as Map<String, dynamic>;
      final id = body['id'] as String;
      strokes[id] = body;
      return _json({...body, 'collectionName': 'canvas_strokes'}, 200);
    }
    return _json({'code': 404, 'message': 'nf', 'data': {}}, 404);
  }
}

Future<void> _drain(OutboxService ob, {int rounds = 40}) async {
  for (var i = 0; i < rounds; i++) {
    if (ob.pendingCount.value == 0) return;
    await ob.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late OutboxService ob;
  late _Server server;
  late File fill;

  setUp(() async {
    await LocalStore.instance.initWith(databaseFactoryMemory, 'stroke_image_add.db');
    ob = OutboxService.instance;
    await ob.clear();
    server = _Server();
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((r) => server.handle(r)),
    ));
    final dir = await Directory.systemTemp.createTemp('tog12_fill');
    fill = File('${dir.path}/fill_1792630961924_14.png');
    // Настоящий PNG 1×1: сервер в тесте его не разбирает, но пусть будет файл.
    await fill.writeAsBytes(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
  });

  Map<String, dynamic> payload(String clientId) {
    final id = strokeRecordId('g1', 'c1', clientId);
    final stroke = DrawStroke(
      id: id,
      clientId: clientId,
      userId: 'me',
      colorValue: 0xFFFF0000,
      strokeWidth: 0,
      points: const [],
      orderIndex: 14,
      imageUrl: 'file://${fill.path}',
      imageX: 0.5,
      imageY: 0.5,
      imageWidth: 1,
      imageHeight: 1,
      imageRotation: 0,
    );
    return {
      'id': id,
      'groupId': 'g1',
      'canvasId': 'c1',
      'path': fill.path,
      'stroke': stroke.toFirestore(),
    };
  }

  test('заливка без сети досылается: сперва файл, потом мазок с тем же id', () async {
    final p = payload('fill_1792630961924_14');
    await ob.enqueue('strokeImageAdd', p);
    await _drain(ob);

    expect(ob.pendingCount.value, 0);
    expect(server.mediaUploads, hasLength(1));
    final saved = server.strokes[p['id']];
    expect(saved, isNotNull, reason: 'Мазок лёг под id, который знает экран');
    final url = (saved!['data'] as Map)['imageUrl'] as String;
    expect(url, startsWith('pb://media/${server.mediaUploads.single}/'),
        reason: 'Партнёр получает ссылку на файл, а не путь на моём телефоне');
  });

  test('сбой загрузки картинки оставляет заливку в очереди', () async {
    server.mediaDown = true;
    await ob.enqueue('strokeImageAdd', payload('fill_1792630961924_15'));
    await _drain(ob, rounds: 1);

    expect(ob.pendingCount.value, 1, reason: 'Дошлём, когда сеть оживёт');
    expect(server.strokes, isEmpty);
  });

  test('отмена снимает из очереди и не дошедшую заливку', () async {
    server.mediaDown = true;
    final p = payload('fill_1792630961924_16');
    await ob.enqueue('strokeImageAdd', p);
    await _drain(ob, rounds: 1);
    await ob.enqueue('strokeCancel', {'id': p['id']});

    expect(ob.pendingCount.value, 0);
    server.mediaDown = false;
    await _drain(ob);
    expect(server.strokes, isEmpty, reason: 'Отменённая заливка не всплывает');
  });
}
