import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Поле, которого нет в одном из четырёх мест, теряется МОЛЧА — и PocketBase,
/// и hotpath отвечают на неизвестное поле успехом, просто выбрасывая его.
/// В этом проекте так уже терялись ссылки желаний, заметка виджета и обложка
/// роликов, поэтому у фигурок связка проверяется тестом.
void main() {
  const noteFields = [
    'note_url',
    'note_ms',
    'note_shape',
    'note_thumb',
    'note_seen_at',
    'note_hearts',
  ];

  test('поля фигурки объявлены в схеме коллекции', () {
    final raw = File('pocketbase/collections_schema.json').readAsStringSync();
    final decoded = jsonDecode(raw);
    final list = decoded is List
        ? decoded
        : (decoded['collections'] as List? ?? const []);
    final chat = list.firstWhere((c) => c['name'] == 'chat_messages');
    final fields = (chat['fields'] ?? chat['schema']) as List;
    final names = fields.map((f) => f['name']).toSet();
    for (final f in noteFields) {
      expect(names, contains(f), reason: 'нет в collections_schema.json: $f');
    }
  });

  test('поля фигурки знает hotpath — иначе запись их выбросит', () {
    final src = File('pocketbase/hotpath/hotpath.py').readAsStringSync();
    final chatBlock = src.split('"chat_messages": {')[1].split('"sortable"')[0];
    for (final f in noteFields) {
      expect(chatBlock, contains('"$f"'), reason: 'нет в COLLECTIONS: $f');
    }
  });

  test('колонки заведены миграцией Postgres', () {
    final sql = File('pocketbase/hotpath/note_fields.sql').readAsStringSync();
    for (final f in noteFields) {
      expect(sql, contains(f), reason: 'нет в note_fields.sql: $f');
    }
  });

  test('отправка кладёт поля фигурки в тело запроса', () {
    final src = File('lib/services/pb_data_service.dart').readAsStringSync();
    final body = src.split('Future<bool> chatSend(')[1].split('return _upsertById')[0];
    for (final f in ['note_url', 'note_ms', 'note_shape', 'note_thumb']) {
      expect(body, contains("'$f'"), reason: 'chatSend не шлёт $f');
    }
  });

  test('смотрящему открыты только отметка просмотра и сердечки', () {
    final src = File('pocketbase/hotpath/hotpath.py').readAsStringSync();
    final guard = src.split('if meta["guard"] == "chat":')[1].split('return _err(403')[0];
    expect(guard, contains('note_seen_at'));
    expect(guard, contains('note_hearts'));
    // Ссылку на файл и форму чужой правит только автор.
    expect(guard, isNot(contains('note_url')));
    expect(guard, isNot(contains('note_shape')));
  });

  test('сохранение в галерею ходит в роут, который объявлен на сервере', () {
    final client = File('lib/services/note_export_service.dart').readAsStringSync();
    final server = File('pocketbase/hotpath/hotpath.py').readAsStringSync();
    expect(client, contains('/api/note/export'));
    expect(server, contains('@app.get("/api/note/export")'));
    // Сервер отдаёт файл только участнику пары — проверка обязана остаться.
    final route = server.split('async def note_export(')[1].split('@app.get')[0];
    expect(route, contains('not your message'));
    expect(route, contains('groups'));
  });

  test('форма для экспорта берётся из того же профиля, что и в приложении', () {
    final shapes = jsonDecode(File('tools/note_shapes.json').readAsStringSync())
        as Map<String, dynamic>;
    final dart = File('lib/widgets/chat/note_shapes.dart').readAsStringSync();
    for (final id in shapes.keys) {
      expect(dart, contains("id: '$id'"), reason: 'формы разошлись: $id');
    }
    expect(shapes.length, 10);
  });

  test('модель читает все поля из записи', () {
    final src = File('lib/models/chat_msg.dart').readAsStringSync();
    for (final f in noteFields) {
      expect(src, contains("m['$f']"), reason: 'ChatMsg.fromPb не читает $f');
    }
  });
}
