import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/pb_errors.dart';

/// Правка воспоминания, которого на сервере уже нет.
///
/// Найдено 10.11.2026 по живому телефону (iPhone, 1.42): партнёр удалил своё
/// воспоминание, а на втором телефоне оно осталось в кэше с правкой в очереди.
/// Правка получала 404, приложение шло создавать запись заново с прежним
/// автором, сервер отказывал (автор — только сам), и так без конца: пара
/// запросов каждые 20–30 секунд сутками, в очереди 359 копий одной правки,
/// плашка «Не сохранилось» не уходила.
void main() {
  group('записи нет на сервере: создавать ли её заново', () {
    test('чужую запись заново не создаём — правка считается выполненной', () {
      expect(missingRecordIsDone(authorUid: 'партнёр', myUid: 'я'), isTrue);
    });

    test('свою запись создаём: это ещё не доехавшее воспоминание', () {
      expect(missingRecordIsDone(authorUid: 'я', myUid: 'я'), isFalse);
    });

    test('автор или свой номер неизвестны — ведём себя как раньше', () {
      expect(missingRecordIsDone(authorUid: '', myUid: 'я'), isFalse);
      expect(missingRecordIsDone(authorUid: 'партнёр', myUid: ''), isFalse);
    });

    test('сохранение воспоминания ходит через это правило и чистит кэш', () {
      final source =
          File('lib/services/pb_data_service.dart').readAsStringSync();
      final start = source.indexOf('Future<bool> upsertMemory(');
      final body = source.substring(start, source.indexOf('Future<bool> patchMemory('));
      expect(body, contains('missingRecordIsDone('));
      expect(body, contains("deleteRecord('memories', id)"),
          reason: 'запись-призрак должна уйти из ленты этого телефона');
    });
  });

  group('копии одной правки в очереди', () {
    late OutboxService ob;

    setUp(() async {
      await LocalStore.instance.initWith(databaseFactoryMemory, 'ghost.db');
      ob = OutboxService.instance;
      await ob.clear();
    });

    tearDown(() => ob.applyOverride = null);

    Future<void> settle() async {
      for (var i = 0; i < 300; i++) {
        if (ob.pendingCount.value == 0) return;
        await ob.flush();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('«Повторить» возвращает в очередь одну правку записи, а не все копии',
        () async {
      ob.applyOverride = (type, payload) async => false; // сервер отказывает
      // Три раза подряд: правка сдаётся, человек правит запись снова.
      for (var round = 0; round < 3; round++) {
        await ob.enqueue('memoryUpsert', {
          'groupId': 'g',
          'id': 'ghost',
          'data': {'title': 'версия $round'},
        });
        await settle();
      }
      expect(ob.poisonCount.value, 3);

      var applied = 0;
      Map<String, dynamic>? last;
      ob.applyOverride = (type, payload) async {
        applied++;
        last = payload;
        return true;
      };
      await ob.retryPoison();
      await settle();

      expect(applied, 1, reason: 'одной записи — одна правка, последняя');
      expect((last?['data'] as Map)['title'], 'версия 2');
      expect(ob.poisonCount.value, 0);
      expect(ob.pendingCount.value, 0);
    });

    test('разные записи при повторе не склеиваются', () async {
      ob.applyOverride = (type, payload) async => false;
      for (final id in ['a', 'b']) {
        await ob.enqueue('memoryUpsert', {'groupId': 'g', 'id': id, 'data': {}});
      }
      await settle();
      expect(ob.poisonCount.value, 2);

      final seen = <String>[];
      ob.applyOverride = (type, payload) async {
        seen.add(payload['id'] as String);
        return true;
      };
      await ob.retryPoison();
      await settle();
      expect(seen..sort(), ['a', 'b']);
    });
  });
}
