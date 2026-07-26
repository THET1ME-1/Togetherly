import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sembast/utils/sembast_import_export.dart';

/// Разовый перенос офлайн-кэша из открытого файла в зашифрованный.
///
/// Работает один раз на устройство: после переноса открытого файла на диске не
/// остаётся, и следующий запуск сразу открывает зашифрованную базу.
///
/// Перенос идёт через `exportDatabase`/`importDatabase`, поэтому переезжают ВСЕ
/// сторы, включая `outbox` — очередь ещё не отправленных сообщений живёт в том
/// же файле, и терять её нельзя.
class CacheMigration {
  CacheMigration._();

  /// Переносит [plainPath] → [encryptedPath]. Возвращает true, если данные
  /// действительно переехали.
  ///
  /// Открытый файл удаляется в ЛЮБОМ исходе, включая ошибку: смысл всей затеи в
  /// том, чтобы переписки не осталось на диске в читаемом виде. Кэш
  /// восстанавливается с сервера, поэтому потеря содержимого безопасна.
  static Future<bool> plainToEncrypted({
    required DatabaseFactory factory,
    required String plainPath,
    required String encryptedPath,
    required SembastCodec codec,
  }) async {
    if (!await File(plainPath).exists()) return false;

    Map<String, Object?>? dump;
    try {
      final old = await factory.openDatabase(plainPath);
      dump = await exportDatabase(old);
      await old.close();
    } catch (e) {
      debugPrint('CacheMigration: открытый кэш не прочитался ($e), удаляю');
      await _drop(factory, plainPath);
      return false;
    }

    final stores = dump['stores'];
    if (stores is! List || stores.isEmpty) {
      // Пустая или битая база — переносить нечего, зашифрованную создаст init().
      await _drop(factory, plainPath);
      return false;
    }

    try {
      final fresh = await importDatabase(
        dump,
        factory,
        encryptedPath,
        codec: codec,
      );
      await fresh.close();
    } catch (e) {
      debugPrint('CacheMigration: перенос не удался ($e); '
          'кэш и очередь отправки будут собраны заново');
      await _drop(factory, plainPath);
      return false;
    }

    await _drop(factory, plainPath);
    debugPrint('CacheMigration: кэш перенесён в зашифрованную базу');
    return true;
  }

  static Future<void> _drop(DatabaseFactory factory, String path) async {
    try {
      await factory.deleteDatabase(path);
    } catch (e) {
      debugPrint('CacheMigration: не удалось удалить $path: $e');
    }
  }
}
