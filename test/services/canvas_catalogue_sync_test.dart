import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/canvas_meta.dart';
import 'package:love_app/services/canvas_storage_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// Удалённый холст не воскресает (TOG-12, 22.10.2026).
///
/// Жалоба: «почему холсты нельзя удалять». Галерея при открытии слала на
/// сервер ВСЕ свои холсты, в том числе удалённые партнёром, и тот заводился
/// снова у обоих. Каталог, ставший пустым, холст не убирал вовсе, а пустой
/// список засевался «Canvas 1».
http.Response _json(Object body, int code) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _CatalogueServer {
  _CatalogueServer(this.canvasIds);

  /// Холсты, которые лежат в каталоге на сервере.
  final Set<String> canvasIds;
  final List<String> created = [];

  static final _canvasInFilter = RegExp(r"canvas_id\s*=\s*'([^']+)'");

  Map<String, dynamic> _rec(String canvasId) => {
        'id': 'r${canvasId.hashCode.abs().toString().padLeft(14, '0').substring(0, 14)}',
        'collectionId': 'canvas_catalogue',
        'collectionName': 'canvas_catalogue',
        'group_id': 'g1',
        'canvas_id': canvasId,
        'name': canvasId,
        'created_at': 0,
        'updated_at': 0,
      };

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    if (path == '/api/collections/canvas_catalogue/records') {
      if (req.method == 'GET') {
        final m = _canvasInFilter.firstMatch(req.url.queryParameters['filter'] ?? '');
        final items = [
          for (final id in canvasIds)
            if (m == null || m.group(1) == id) _rec(id),
        ];
        return _json({
          'page': 1,
          'perPage': 500,
          'totalItems': items.length,
          'totalPages': 1,
          'items': items,
        }, 200);
      }
      if (req.method == 'POST') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final id = body['canvas_id'] as String;
        created.add(id);
        canvasIds.add(id);
        return _json(_rec(id), 200);
      }
    }
    if (req.method == 'PATCH' &&
        path.startsWith('/api/collections/canvas_catalogue/records/')) {
      return _json({'id': path.split('/').last}, 200);
    }
    // Счётчик рисунков пары и прочее — не предмет проверки.
    return _json({}, 200);
  }
}

CanvasMeta _canvas(String id, {bool? onServer, DateTime? at}) => CanvasMeta(
      id: id,
      name: id,
      createdAt: at ?? DateTime(2026, 9, 1),
      updatedAt: at ?? DateTime(2026, 9, 1),
      onServer: onServer,
    );

Future<void> _seedLocal(List<CanvasMeta> list) async {
  SharedPreferences.setMockInitialValues({
    'canvases_v1_me_g1': jsonEncode(list.map((c) => c.toJson()).toList()),
  });
}

Map<String, dynamic> _remote(String id) => {
      'id': id,
      'name': id,
      'createdAt': DateTime(2026, 9, 1).millisecondsSinceEpoch,
      'updatedAt': DateTime(2026, 9, 1).millisecondsSinceEpoch,
    };

void main() {
  late _CatalogueServer server;
  final storage = CanvasStorageService.instance;

  void serve(Set<String> remote) {
    server = _CatalogueServer(remote);
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient(server.handle),
    ));
  }

  setUp(() => storage.debugReset());

  test('холст, удалённый партнёром, бутстрап не заводит снова', () async {
    // У меня холст лежит с прошлого раза, партнёр его удалил. Галерея
    // открылась, и досылка успевает раньше, чем пришёл каталог.
    await _seedLocal([_canvas('canvas_x'), _canvas('canvas_y')]);
    serve({'canvas_y'});

    await storage.pushAllToFirebase('me', 'g1');

    expect(server.created, isNot(contains('canvas_x')),
        reason: 'Удалённый партнёром холст не возвращается на сервер');
  });

  test('каталог стал пустым — удалённый холст уходит и у меня', () async {
    await _seedLocal([_canvas('canvas_x')]);
    serve({});

    await storage.mergeRemoteCanvases('me', 'g1', const []);

    expect(await storage.getCanvases('me', groupId: 'g1'), isEmpty);
  });

  test('каталог без холста — холст, который сервер видел, уходит', () async {
    await _seedLocal([_canvas('canvas_x', onServer: true), _canvas('canvas_y')]);
    serve({'canvas_y'});

    await storage.mergeRemoteCanvases('me', 'g1', [_remote('canvas_y')]);

    final ids = (await storage.getCanvases('me', groupId: 'g1')).map((c) => c.id);
    expect(ids, ['canvas_y']);
  });

  test('холст, не дошедший до сервера, остаётся и досылается', () async {
    await _seedLocal([_canvas('canvas_new', onServer: false, at: DateTime.now())]);
    serve({});

    await storage.mergeRemoteCanvases('me', 'g1', const []);
    expect((await storage.getCanvases('me', groupId: 'g1')).map((c) => c.id),
        ['canvas_new'],
        reason: 'Его нет на сервере, потому что он туда ещё не дошёл');

    await storage.pushAllToFirebase('me', 'g1');
    expect(server.created, ['canvas_new']);
    final after = await storage.getCanvases('me', groupId: 'g1');
    expect(after.single.onServer, isTrue,
        reason: 'Дошедший холст дальше уходит вместе с каталогом');
  });

  test('удаление последнего холста не заводит «Canvas 1»', () async {
    await _seedLocal([_canvas('canvas_x', onServer: true)]);
    serve({'canvas_x'});

    await storage.deleteCanvas('me', 'canvas_x', groupId: 'g1');

    expect(await storage.getCanvases('me', groupId: 'g1'), isEmpty);
  });

  test('новый холст после ответа сервера помечается дошедшим', () async {
    await _seedLocal(const []);
    serve({});

    final meta = await storage.createCanvas('me', groupId: 'g1');
    await storage.debugIdle();

    final saved = (await storage.getCanvases('me', groupId: 'g1'))
        .firstWhere((c) => c.id == meta.id);
    expect(saved.onServer, isTrue);
    expect(server.created, [meta.id]);
  });
}
