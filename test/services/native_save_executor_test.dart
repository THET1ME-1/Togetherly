// Нативная фоновая запись со стороны Dart.
//
// Очередь отдаёт файл нативу (Android — своя служба с уведомлением, iPhone —
// фоновая сессия URLSession) и ждёт ответа. Натив работает без Dart: пока
// приложение свёрнуто или выгружено, он качает и кладёт в галерею сам, а
// Dart при следующем опросе забирает готовое. Здесь канал подменён: видно
// ровно разговор Dart с нативом.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_media.dart';
import 'package:love_app/services/media_save_queue.dart';
import 'package:love_app/services/native_save_executor.dart';

const _channel = MethodChannel('test/gallery');

SaveItem _item(String ref, {int i = 0}) => SaveItem(
      memoryId: 'm1',
      takenAt: DateTime(2026, 9, 5, 13, 5, 7),
      latitude: 46.9,
      longitude: 29.1,
      file: MediaFile(ref: ref, kind: SaveKind.photo, index: i),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late List<Map<String, Object?>> results;

  NativeSaveExecutor exec() => NativeSaveExecutor(
        channel: _channel,
        pollEvery: const Duration(milliseconds: 2),
        sourceOf: (f) async => f.ref.startsWith('localfile://')
            ? {'path': f.ref.substring('localfile://'.length)}
            : {'url': 'https://togetherly.day/api/files/${f.key.substring(5)}?token=t'},
      );

  setUp(() {
    calls = [];
    results = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'engineStatus':
          final out = List<Map<String, Object?>>.of(results);
          return {'results': out, 'pending': 0};
        case 'engineAck':
          final keys = List<String>.from((call.arguments as Map)['keys'] as List);
          results.removeWhere((r) => keys.contains(r['key']));
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('файл уходит нативу со ссылкой, датой, местом и именем', () async {
    final e = exec();
    final f = e.run(_item('pb://media/r/f.webp'), hidden: false, title: 'Лето');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final submit = calls.firstWhere((c) => c.method == 'engineSubmit');
    final a = Map<String, Object?>.from(submit.arguments as Map);
    expect(a['key'], 'pb://media/r/f.webp');
    expect(a['url'], startsWith('https://togetherly.day/api/files/media/r/f.webp'));
    expect(a['kind'], 'photo');
    expect(a['takenAt'], DateTime(2026, 9, 5, 13, 5, 7).millisecondsSinceEpoch);
    expect(a['latitude'], 46.9);
    expect(a['name'], 'Togetherly_20260905_130507_01.webp');
    expect(a['album'], 'Togetherly');
    expect(a['title'], 'Лето');
    expect((a['labels'] as Map).keys, containsAll(['saving', 'done', 'failed', 'stop']));

    results.add({'key': 'pb://media/r/f.webp', 'code': 'OK', 'uri': 'content://1'});
    expect(await f, 'content://1');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final ack = calls.lastWhere((c) => c.method == 'engineAck');
    expect((ack.arguments as Map)['keys'], ['pb://media/r/f.webp']);
  });

  test('файл с телефона уходит путём, без сети', () async {
    final e = exec();
    final f = e.run(_item('localfile:///data/x/1.jpg'), hidden: false);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final a = Map<String, Object?>.from(
        calls.firstWhere((c) => c.method == 'engineSubmit').arguments as Map);
    expect(a['path'], '/data/x/1.jpg');
    expect(a.containsKey('url'), isFalse);
    results.add({'key': 'localfile:///data/x/1.jpg', 'code': 'OK', 'uri': ''});
    await f;
  });

  test('отказ в доступе и остановка из уведомления', () async {
    final e = exec();
    final denied = e.run(_item('pb://media/r/a.webp'), hidden: false);
    final stopped = e.run(_item('pb://media/r/b.webp', i: 1), hidden: false);
    results
      ..add({'key': 'pb://media/r/a.webp', 'code': 'ACCESS_DENIED'})
      ..add({'key': 'pb://media/r/b.webp', 'code': 'CANCELLED'});
    await expectLater(denied, throwsA(isA<GalleryAccessDenied>()));
    await expectLater(stopped, throwsA(isA<SaveCancelled>()));
  });

  test('обрыв после всех нативных повторов — обычная ошибка', () async {
    final e = exec();
    final f = e.run(_item('pb://media/r/a.webp'), hidden: false);
    results.add({'key': 'pb://media/r/a.webp', 'code': 'FAILED', 'error': 'HTTP 404'});
    await expectLater(f, throwsA(isA<Exception>()));
  });

  test('крестик снимает файлы у натива и сразу отпускает очередь', () async {
    final e = exec();
    final f = e.run(_item('pb://media/r/a.webp'), hidden: false);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final stopped = expectLater(f, throwsA(isA<SaveCancelled>()));
    await e.cancel([_item('pb://media/r/a.webp')]);
    await stopped;
    final c = calls.lastWhere((c) => c.method == 'engineCancel');
    expect((c.arguments as Map)['keys'], ['pb://media/r/a.webp']);
  });

  test('при старте забирается сделанное без приложения', () async {
    results
      ..add({'key': 'pb://media/r/a.webp', 'code': 'OK', 'uri': 'x'})
      ..add({'key': 'pb://media/r/b.webp', 'code': 'FAILED', 'error': 'x'});
    final done = await exec().recover();
    expect(done, ['pb://media/r/a.webp']);
    // Разобранное подтверждено — натив его забывает.
    expect(results, isEmpty);
  });

  test('без нативной части очередь узнаёт об этом сразу', () async {
    messenger.setMockMethodCallHandler(_channel, null);
    final e = exec();
    await expectLater(
        e.run(_item('pb://media/r/a.webp'), hidden: false), throwsA(anything));
    expect(await e.recover(), isEmpty);
  });
}
