import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/offline/cache_cipher.dart';
import 'package:love_app/services/offline/cache_migration.dart';
import 'package:sembast/sembast_io.dart';

/// Шифрование офлайн-кэша: без него вся переписка пары лежала на диске открытым
/// json (`files/offline/pb_cache.db`) и уезжала в автобэкап Google.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cache_cipher_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('CacheCipher', () {
    test('ключ — 32 случайных байта, два вызова дают разные ключи', () {
      final a = CacheCipher.generateKey();
      final b = CacheCipher.generateKey();
      expect(a.length, 32);
      expect(b.length, 32);
      expect(a, isNot(equals(b)));
    });

    test('раскодирует обратно ровно то, что закодировали', () {
      final codec = CacheCipher.codec(CacheCipher.generateKey()).codec!;
      final value = {
        'id': 'msg1',
        'text': 'люблю тебя',
        'ts': 1753500000000,
        'reactions': {'u1': '❤️'},
        'nested': [
          1,
          true,
          null,
          {'a': 'b'},
        ],
      };
      expect(codec.decode(codec.encode(value)), equals(value));
    });

    test('в шифртексте нет открытого текста', () {
      final codec = CacheCipher.codec(CacheCipher.generateKey()).codec!;
      final line = codec.encode({'text': 'секретная фраза'});
      expect(line.contains('секретная'), isFalse);
      expect(line.contains('text'), isFalse);
    });

    test('одно значение шифруется каждый раз по-новому (случайный IV)', () {
      final codec = CacheCipher.codec(CacheCipher.generateKey()).codec!;
      const value = {'text': 'одно и то же'};
      expect(codec.encode(value), isNot(equals(codec.encode(value))));
    });

    test('чужой ключ не расшифровывает', () {
      final mine = CacheCipher.codec(CacheCipher.generateKey()).codec!;
      final theirs = CacheCipher.codec(CacheCipher.generateKey()).codec!;
      final line = mine.encode({'text': 'не для чужих глаз'});
      expect(() => theirs.decode(line), throwsA(anything));
    });

    test('подпись зависит от ключа: чужой ключ базу не откроет', () async {
      final key = CacheCipher.generateKey();
      final path = '${tmp.path}/enc.db';
      final store = stringMapStoreFactory.store('col_chat_messages');

      final db = await databaseFactoryIo.openDatabase(path,
          codec: CacheCipher.codec(key));
      await store.record('m1').put(db, {'text': 'привет'});
      await db.close();

      final reopened = await databaseFactoryIo.openDatabase(path,
          codec: CacheCipher.codec(key));
      expect((await store.record('m1').get(reopened))?['text'], 'привет');
      await reopened.close();

      await expectLater(
        databaseFactoryIo.openDatabase(path,
            codec: CacheCipher.codec(CacheCipher.generateKey())),
        throwsA(anything),
      );
    });

    test('на диске файла базы нет открытого текста сообщения', () async {
      final path = '${tmp.path}/ondisk.db';
      final db = await databaseFactoryIo.openDatabase(path,
          codec: CacheCipher.codec(CacheCipher.generateKey()));
      await stringMapStoreFactory
          .store('col_chat_messages')
          .record('m1')
          .put(db, {'text': 'совершенно секретно', 'user_name': 'Саша'});
      await db.close();

      final raw = await File(path).readAsString();
      expect(raw.contains('совершенно секретно'), isFalse);
      expect(raw.contains('Саша'), isFalse);
    });
  });

  group('миграция открытого кэша в зашифрованный', () {
    test('переносит записи всех сторов, включая очередь отправки', () async {
      final plain = '${tmp.path}/pb_cache.db';
      final enc = '${tmp.path}/pb_cache_enc.db';
      final messages = stringMapStoreFactory.store('col_chat_messages');
      final outbox = intMapStoreFactory.store('outbox');
      final meta = stringMapStoreFactory.store('sync_meta');

      final old = await databaseFactoryIo.openDatabase(plain);
      await messages.record('m1').put(old, {'id': 'm1', 'text': 'скучаю'});
      await outbox.record(1).put(old, {'op': 'chatUpsert', 'id': 'm2'});
      await meta.record('_owner').put(old, {'uid': 'u1'});
      await old.close();

      final key = CacheCipher.generateKey();
      final moved = await CacheMigration.plainToEncrypted(
        factory: databaseFactoryIo,
        plainPath: plain,
        encryptedPath: enc,
        codec: CacheCipher.codec(key),
      );

      expect(moved, isTrue);
      expect(await File(plain).exists(), isFalse,
          reason: 'открытый файл обязан исчезнуть, иначе утечка остаётся');

      final db =
          await databaseFactoryIo.openDatabase(enc, codec: CacheCipher.codec(key));
      expect((await messages.record('m1').get(db))?['text'], 'скучаю');
      expect((await outbox.record(1).get(db))?['op'], 'chatUpsert');
      expect((await meta.record('_owner').get(db))?['uid'], 'u1');
      await db.close();

      expect((await File(enc).readAsString()).contains('скучаю'), isFalse);
    });

    test('нечего переносить — возвращает false и ничего не создаёт', () async {
      final moved = await CacheMigration.plainToEncrypted(
        factory: databaseFactoryIo,
        plainPath: '${tmp.path}/нет-такого.db',
        encryptedPath: '${tmp.path}/enc.db',
        codec: CacheCipher.codec(CacheCipher.generateKey()),
      );
      expect(moved, isFalse);
      expect(await File('${tmp.path}/enc.db').exists(), isFalse);
    });

    test('битый открытый файл не роняет запуск и удаляется', () async {
      final plain = '${tmp.path}/broken.db';
      await File(plain).writeAsString('{это не sembast\nмусор');

      final moved = await CacheMigration.plainToEncrypted(
        factory: databaseFactoryIo,
        plainPath: plain,
        encryptedPath: '${tmp.path}/enc.db',
        codec: CacheCipher.codec(CacheCipher.generateKey()),
      );

      expect(moved, isFalse);
      expect(await File(plain).exists(), isFalse,
          reason: 'нечитаемый открытый кэш всё равно уносим с диска');
    });
  });
}
